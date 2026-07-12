open Helpers

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


let update todo_path line new_content effects =
	let* (todos, _, _) = extract line todo_path effects.read in
  let updated = todos |> List.mapi (fun idx content -> if idx = line - 1 then new_content else content) in
  let* _ = effects.write updated todo_path in
	Ok new_content

let toggle_doing line todo_path effects =
	let toggle_tag str =
		if string_contains ~needle:"@doing" str then
			replace_word ~target:"@doing" ~replacement:"" str
		else
		str ^ " @doing"
	in
	let* (todos, todo, _) = extract line todo_path effects.read in
	let updated = todos |> List.mapi (fun idx content ->
	 if idx = line - 1 then toggle_tag content else content
	) in
	let* _ = effects.write updated todo_path in
	Ok (toggle_tag todo)

let remove line todo_path effects =
	let* (_, removed, updated) = extract line todo_path effects.read in
	let* _ = effects.write updated todo_path in
	Ok removed

let complete line todo_path done_path effects =
	let* (_, todo, updated) = extract line todo_path effects.read in
	let* done_todos = effects.read done_path in
	let todo = replace_word ~target:"@doing" ~replacement: "" todo in
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

	let* msg =
		let todo = replace_word ~target:"@doing" ~replacement:"" todo in
		if open_editor then
			let* edited = effects.editor todo in
			if edited = "" then Error (`CommitError "Commit aborted due to empty message") else Ok edited
		else Ok (todo)
	in

	let* _ = effects.commit msg repo in
	let* done_todos = effects.read done_path in
	let done_formatted = effects.now () ^ " " ^ msg in
	let* _ = effects.write (done_formatted :: done_todos) done_path in
	let* _ = effects.write updated todo_path in
	Ok msg

let projects effects = effects.projects()

let edit line todo_path effects =
	let* (todos, todo, _) = extract line todo_path effects.read in
	let* edited = effects.editor todo in
	if edited = "" || edited = todo then Ok "Cancel editing" else
	let updated = todos |> List.mapi (fun idx content -> if idx = line - 1 then edited else content) in
	let* _ = effects.write updated todo_path in
	Ok edited

let edit_file path effects =
	let* todos = effects.read path in
	let content = String.concat "\n" todos in
	let* edited = effects.editor content in
	if edited = "" || edited = content then Ok "Cancel editing" else
	let updated = String.split_on_char '\n' edited in
	let* _ = effects.write updated path in
	Ok edited

let project name effects =
  let* projects = projects effects in

  match projects |> sort_matches |> List.find_opt (fun path -> List.mem name (String.split_on_char '/' path)) with
  | Some found_path -> list found_path effects
  | None -> Error `FileSystem
