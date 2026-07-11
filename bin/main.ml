open T
open Effects

let get_todo_path () =
  let current_dir = Sys.getcwd () in
  Filename.concat current_dir ".todo"

let get_done_path () =
  let current_dir = Sys.getcwd () in
  Filename.concat current_dir ".done"

(* dispatch cmd -> result *)
let dispatch cmd todo_path done_path effects : (string, _) result = match cmd with
	| Count ->
		let* todos = list todo_path effects in
		Ok (string_of_int (List.length todos))
	| List path ->
		let* todos = list path effects in
		Ok (String.concat "\n" todos)
	| ListRange (path, range) ->
		let* todos = list path effects in
		let filtered = todos |> List.filteri (fun i _ -> List.mem (i + 1) range) in
		Ok (String.concat "\n" filtered)
	| Add (path, todo) ->
		let* added = add todo path effects in
		Ok added
	| Complete (path, lines) ->
		let* completed = complete (List.hd lines) path done_path effects in
		Ok completed
	| Remove (path, lines) ->
		let* removed = remove (List.hd lines) path effects in
		Ok removed
	| Edit (path, line) ->
		let* edited = edit line path effects in
		Ok edited
	| Commit (path, line, editing) ->
		let* msg = T.commit line path done_path editing effects in
		Ok msg
	| Echo (path, line) ->
		let* todos = list path effects in
		begin match List.nth_opt todos (line - 1) with
		| Some todo -> Ok todo
		| None -> Error (`WrongLine line)
		end
	| EditFile path -> Ok "@todo: edit file"
	| Doing (path, line) ->
		let* todo = toggle_doing line path effects in
		Ok todo
	| ListDoing path ->
		let* todos = list_doing path effects in
		Ok (String.concat "\n" todos)
	| ListProjects ->
		let* projects = T.projects effects in
		Ok (String.concat "\n" projects)
	| ListDoingAcrossProjects ->
		let* doing = list_doing_across_projects effects in
		let lines =
			List.concat_map (fun (path, doings) ->
				(path ^ ":") :: List.map (fun d -> " " ^ d) doings
			) doing
		in
		Ok (String.concat "\n" lines)


let () =
  let cli_args = match (Array.to_list Sys.argv) with [] -> [] | _::tl -> tl in
  let effects = (fx()) in
  let todo_path = get_todo_path() in
  let done_path = get_done_path() in
  match command_router todo_path cli_args effects with
  | Some cmd ->
  		begin match (dispatch cmd todo_path done_path effects) with
    	| Ok msg -> print_endline msg
      | Error (`NoRepository) -> print_endline "No repository found";
      | Error (`CommitError msg) -> print_endline ("Commit failed: " ^ msg);
      | Error (`FileSystem) -> print_endline "Filesystem error";
      | Error (`Editor) -> print_endline "Editor error";
      | Error (`WrongLine n) -> print_endline (Printf.sprintf "No todo at line %d" n);
      end
  | None -> print_endline "@todo: none"
