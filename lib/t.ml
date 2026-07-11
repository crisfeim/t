
type error =
	[
  | `FileSystem
  | `WrongLine of int
  | `Editor
  | `NoRepository
  | `CommitError of string
  ]

(* Custom bindings *)
let ( let*?) = Option.bind
let ( let* )
	(x : ('a, [< error]) result)
	(f : 'a -> ('b, [> error]) result) : ('b, error) result =
  match x with
  | Ok v -> f v
  | Error e -> Error (e :> error)

(* Types as documentation *)
type todo    = string
type path    = string
type content = string
type message = string

type repo = { path: path; system: string }

type effects = {
	projects: unit -> (path list, [`FileSystem]) result;
	read    : path -> (string list, [`FileSystem]) result;
	write   : todo list -> path -> (unit, [`FileSystem]) result;
	now     : unit -> string;
	editor  : content -> (string, [`Editor]) result;
	commit  : message -> repo -> (unit, error) result;
  get_repo: path -> repo option
}

let list todo_path effects =
	let* todos = effects.read todo_path in
	let formatted = todos |> List.mapi (fun idx content -> string_of_int (idx + 1) ^ " " ^ content) in
	Ok formatted

let string_contains ~needle haystack =
  let nlen = String.length needle in
  let hlen = String.length haystack in
  let rec loop i =
    if i + nlen > hlen then false
    else if String.sub haystack i nlen = needle then true
    else loop (i + 1)
  in
  if nlen = 0 then true else loop 0

let list_doing todo_path effects =
	let* todos = effects.read todo_path in
	let formatted = todos
		|> List.mapi (fun i todo -> (i + 1, todo))
    |> List.filter (fun (_, todo) -> string_contains ~needle:"@doing" todo)
    |> List.map (fun (i, todo) -> Printf.sprintf "%d %s" i todo) in
	Ok formatted

let list_doing_across_projects effects =
  let* all_projects = effects.projects () in
  let results =
    List.filter_map (fun path ->
      match list_doing path effects with
      | Ok doings when doings <> [] -> Some (path, doings)
      | _ -> None
    ) all_projects
  in
  let sorted = List.sort (fun (a, _) (b, _) -> compare a b) results in
  Ok sorted

let add todo todo_path effects =
	let* todos = effects.read todo_path in
	let updated = todos @ [todo] in
	let* _ = effects.write updated todo_path in
	Ok todo

let extract line todo_path read =
	let* todos = read todo_path in
	if line < 1 || line > List.length todos then Error (`WrongLine line) else
	let updated = todos |> List.filteri (fun idx _ -> idx <> line - 1) in
	let extracted = List.nth todos (line - 1) in
	Ok (todos, extracted, updated)

let remove line todo_path effects =
	let* (_, removed, updated) = extract line todo_path effects.read in
	let* _ = effects.write updated todo_path in
	Ok removed

let complete line todo_path done_path effects =
	let* (_, todo, updated) = extract line todo_path effects.read in
	let* done_todos = effects.read done_path in
	let done_formated = effects.now () ^ " " ^ todo in
	let* _ = effects.write (done_formated :: done_todos) done_path in
	let* _ = effects.write updated todo_path in
	Ok todo

let commit line todo_path done_path open_editor effects =
	let* repo =
		match effects.get_repo todo_path with
		| Some info -> Ok info
		| None -> Error `NoRepository
	in
	let* (todos, todo, updated) = extract line todo_path effects.read in

	let* msg = if open_editor then
		let* edited = effects.editor todo in
		if edited = "" then Error (`CommitError "Commit aborted due to empty message") else Ok edited
		else Ok todo
	in

	let* _ = effects.commit msg repo in
	let* done_todos = effects.read done_path in
	let done_formatted = effects.now () ^ " " ^ msg in
	let* _ = effects.write (done_formatted :: done_todos) done_path in
	let* _ = effects.write updated todo_path in
	Ok ()

let projects effects = effects.projects()

let edit line todo_path effects =
	let* (todos, todo, _) = extract line todo_path effects.read in
	let* edited = effects.editor todo in
	if edited = "" || edited = todo then Ok "Cancel editing" else
	let updated = todos |> List.mapi (fun idx content -> if idx = line - 1 then edited else content) in
	let* _ = effects.write updated todo_path in
	Ok edited

let sort_matches projects =
	List.sort (fun path1 path2 ->
		let count1 = List.length (String.split_on_char '/' path1) in
    let count2 = List.length (String.split_on_char '/' path2) in

    if count1 <> count2 then
      compare count1 count2
    else
    	let len1 = String.length path1 in
     	let len2 = String.length path2 in

      if len1 <> len2 then
     		compare len1 len2
      else
     		String.compare path1  path2
	) projects

let project name effects =
  let* projects = projects effects in

  match projects |> sort_matches |> List.find_opt (fun path -> List.mem name (String.split_on_char '/' path)) with
  | Some found_path -> list found_path effects
  | None -> Error `FileSystem

(* Parser *)
let to_option = function
  | Ok x -> Some x
  | Error _ -> None

type command =
| Count
| List of path
| ListRange of path * int list
| Add of path * string
| Complete of path * int list
| Remove of path * int list
| Edit of path * int
| Commit of path * int * bool
| Echo of path * int
| EditFile of path
| Doing of path * int
| ListDoing of path
| ListProjects
| ListDoingAcrossProjects

let is_cmd operator str =
	String.length str > 1
  && String.get str 0 = operator
  && Option.is_some (int_of_string_opt (String.sub str 1 (String.length str - 1)))

let drop n str =
	if n >=String.length str then ""
	else String.sub str n (String.length str - n)

let is_numeric str = Option.is_some (int_of_string_opt str)

let is_batch_cmd operator str =
	String.length str > 1
  && String.get str 0 = operator
	&& (drop 1 str
		|> String.split_on_char ','
		|> List.for_all is_numeric)

let is_commit_editing str =
	String.length str > 2
	&& String.get str 0 = 'c'
	&& String.get str 1 = ':'

let list_from string = String.split_on_char ',' string

let parse_range str =
  match String.split_on_char '.' str with
  | [left; ""; ""; right] ->
      (match int_of_string_opt left, int_of_string_opt right with
       | Some left, Some right when right >= left -> List.init (right - left + 1) (fun i -> left + i)
       | _ -> [])
  | _ -> []

let parser path args= match args with
	| [] -> Some (List path)
	| [arg] when is_batch_cmd '+' arg -> Some (Complete (path, ((list_from (drop 1 arg)) |> List.map int_of_string)))
	| [arg] when is_batch_cmd '-' arg -> Some (Remove (path, ((list_from (drop 1 arg)) |> List.map int_of_string)))
	| [arg] when is_cmd ':' arg -> Some (Edit (path, int_of_string (drop 1 arg)))
	| [arg] when is_cmd 'c' arg -> Some (Commit (path, int_of_string (drop 1 arg), false))
	| [arg] when is_cmd '@' arg -> Some (Doing (path, int_of_string (drop 1 arg)))
	| [arg] when is_commit_editing arg ->
			let*? line = int_of_string_opt (drop 2 arg) in
			Some (Commit (path, line, true))
	| [arg] when Option.is_some (int_of_string_opt arg) -> Some (Echo (path, int_of_string arg))
	| [arg] when arg = ":" -> Some (EditFile path)
	| [arg] when arg = "@" -> Some (ListDoing path)
	| [arg] when arg = "." -> Some (ListProjects)
	| [arg] when arg = ".@" -> Some (ListDoingAcrossProjects)
	| [arg] when arg = "count" -> Some (Count)
	| [arg] when (parse_range arg <> [])  -> Some (ListRange (path, parse_range arg))
	| args -> Some (Add (path, String.concat " " args))


let first = function
	| first :: _ -> Some first
	| [] -> None

let command_router todo_path args effects =
	let is_project project =
		String.length project > 1 && String.get project 0 = '.' && String.get project 1 <> '@'
	in

	let project_path name all_projects =
		all_projects
			|> List.filter (fun path ->
			     String.split_on_char '/' path |>
			     List.exists (fun part -> part = name))
			|> sort_matches
			|> first
	in

	match args with
		| [project] when is_project project ->
		  let*? all_projects = effects.projects() |> to_option in
			let*? path = project_path (drop 1 project) all_projects in
			Some (List path)
		| [project; args] when is_project project ->
			let*? all_projects = effects.projects() |> to_option in
			let*? path = project_path (drop 1 project) all_projects in
			parser path [args]
		| args ->
			match (args |> first) with
				| Some first when is_project first ->
					let*? all_projects = effects.projects() |> to_option in
					let*? path = project_path (drop 1 first) all_projects in
					let todo = (List.tl args) |> String.concat " " in
					Some (Add (path, todo))
				| _ -> parser todo_path args
