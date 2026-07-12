open Logic

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
| Update of path * int * string
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
	&& Option.is_some (int_of_string_opt (drop 2 str))

let list_from string = String.split_on_char ',' string

let parse_range str =
  match String.split_on_char '.' str with
  | [left; ""; ""; right] ->
      (match int_of_string_opt left, int_of_string_opt right with
       | Some left, Some right when right >= left -> List.init (right - left + 1) (fun i -> left + i)
       | _ -> [])
  | _ -> []

let parser path args = match args with
  | [] -> List path
  | [arg] when is_batch_cmd '+' arg -> Complete (path, ((list_from (drop 1 arg)) |> List.map int_of_string))
  | [arg] when is_batch_cmd '-' arg -> Remove (path, ((list_from (drop 1 arg)) |> List.map int_of_string))
  | [arg] when is_cmd ':' arg -> Edit (path, int_of_string (drop 1 arg))
  | [arg] when is_cmd 'c' arg -> Commit (path, int_of_string (drop 1 arg), false)
  | [arg] when is_cmd '@' arg -> Doing (path, int_of_string (drop 1 arg))
  | [arg] when is_commit_editing arg -> Commit (path, int_of_string (drop 2 arg), true)
  | [arg] when Option.is_some (int_of_string_opt arg) -> Echo (path, int_of_string arg)
  | [arg] when arg = ":" -> EditFile path
  | [arg] when arg = "@" -> ListDoing path
  | [arg] when arg = "." -> ListProjects
  | [arg] when arg = ".@" -> ListDoingAcrossProjects
  | [arg] when arg = "count" -> Count
  | [arg] when (parse_range arg <> [])  -> ListRange (path, parse_range arg)
  | [arg1; arg2] when is_cmd ':' arg1 -> Update (path, int_of_string (drop 1 arg1), arg2)
  | args -> Add (path, String.concat " " args)


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
			Some (parser path [args])
		| args ->
			match (args |> first) with
				| Some first when is_project first ->
					let*? all_projects = effects.projects() |> to_option in
					let*? path = project_path (drop 1 first) all_projects in
					let todo = (List.tl args) |> String.concat " " in
					Some (Add (path, todo))
				| _ -> Some (parser todo_path args)
