open T.Parser
open T.Logic
open Effects

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
	| Update (path ,line, value) ->
		let* updated = update path line value effects in
		Ok updated
	| Commit (path, line, editing) ->
		let* msg = commit line path done_path editing effects in
		Ok msg
	| Echo (path, line) ->
		let* todos = list path effects in
		begin match List.nth_opt todos (line - 1) with
		| Some todo -> Ok todo
		| None -> Error (`WrongLine line)
		end
	| EditFile path ->
			let* edited = edit_file path effects in
			Ok edited
	| Doing (path, line) ->
		let* todo = toggle_doing line path effects in
		Ok todo
	| ListDoing path ->
		let* todos = list_doing path effects in
		Ok (String.concat "\n" todos)
	| ListProjects ->
		let* projects = projects effects in
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
	let args = (Array.to_list Sys.argv) |> Helpers.drop_first in
  let effects = (fx()) in
  let todo_path = Helpers.cwd ".todo" in
  let done_path = Helpers.cwd ".done" in
  match command_router todo_path args effects with
  | Ok cmd ->
		begin match (dispatch cmd todo_path done_path effects) with
   	| Ok msg -> print_endline msg
    | Error (`NoRepository) -> print_endline "No repository found";
    | Error (`CommitError msg) -> print_endline ("Commit failed: " ^ msg);
    | Error (`FileSystem) -> print_endline "Filesystem error";
    | Error (`Editor) -> print_endline "Editor error";
    | Error (`WrongLine n) -> print_endline (Printf.sprintf "No todo at line %d" n);
    end
  | Error (`FileSystem) -> print_endline "Filesystem error"
  | Error (`ProjectNotFound project) -> print_endline ("Project not found: " ^ project)
