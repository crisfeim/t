open T

(* Effects *)
let read_lines file_path =
  try
    let ch = open_in file_path in
    let rec loop acc =
      try
        let line = input_line ch in
        loop (line :: acc)
      with End_of_file ->
        close_in ch;
        List.rev acc
    in
    Ok (loop [])
  with _ ->
    Ok []

let write_lines todos file_path =
  try
    (* Open_trunc empties file so we can override it *)
    let ch = open_out_gen [Open_wronly; Open_creat; Open_trunc; Open_text] 0o666 file_path in
    List.iter (fun todo -> output_string ch (todo ^ "\n")) todos;
    close_out ch;
    Ok ()
  with _ ->
    Error `FileSystem

let editor todo =
  try
    let temp_file = Filename.temp_file "todo_edit" ".txt" in
    let ch = open_out temp_file in
    output_string ch todo;
    close_out ch;
    let editor_cmd =
      try Sys.getenv "EDITOR" with Not_found -> "vi"
    in
    let cmd = Printf.sprintf "%s %s" editor_cmd (Filename.quote temp_file) in
    let exit_code = Sys.command cmd in
    if exit_code <> 0 then begin
      (try Sys.remove temp_file with _ -> ());
      Error `Editor
    end else begin
      let ch = open_in temp_file in
      let rec loop acc =
        try
          let line = input_line ch in
          loop (if acc = "" then line else acc ^ "\n" ^ line)
        with End_of_file -> acc
      in
      let content = loop "" in
      close_in ch;
      (try Sys.remove temp_file with _ -> ());
      Ok content
    end
  with _ -> Error `Editor


let get_repo todo_path =
  let start = Filename.dirname todo_path in
  let rec find current fossil git =
    let fossil =
      if fossil = None && Sys.file_exists (Filename.concat current ".fslckout")
      then Some current else fossil
    in
    let git =
      if git = None && Sys.file_exists (Filename.concat current ".git")
      then Some current else git
    in
    let parent = Filename.dirname current in
    if parent = current then (fossil, git) else find parent fossil git
  in
  match find start None None with
  | Some f, Some g ->
      if String.length f >= String.length g
      then Some { path = f; system = "fossil" }
      else Some { path = g; system = "git" }
  | Some f, None -> Some { path = f; system = "fossil" }
  | None, Some g -> Some { path = g; system = "git" }
  | None, None -> None

let commit message repo =
  let commands = match repo.system with
    | "git" -> [ ["git"; "add"; "-A"]; ["git"; "commit"; "-m"; message] ]
    | "fossil" -> [ ["fossil"; "addremove"]; ["fossil"; "commit"; "-m"; message] ]
    | _ -> []
  in
  match commands with
  | [] -> Error (`CommitError "unhandled vcs")
  | cmds ->
    let err_file = Filename.temp_file "todo_commit_err" ".txt" in
    let result =
      List.fold_left (fun acc args ->
        match acc with
        | Error _ -> acc
        | Ok () ->
          let quoted = List.map Filename.quote args in
          let full_cmd =
            Printf.sprintf "cd %s && %s >/dev/null 2>%s"
              (Filename.quote repo.path)
              (String.concat " " quoted)
              (Filename.quote err_file)
          in
          if Sys.command full_cmd = 0 then Ok ()
          else
            let msg =
              try
                let ch = open_in err_file in
                let content = really_input_string ch (in_channel_length ch) in
                close_in ch; content
              with _ -> "unknown commit error"
            in
            Error (`CommitError msg)
      ) (Ok ()) cmds
    in
    (try Sys.remove err_file with _ -> ());
    result


let find_todos root =
  let exclude_dirs = ["Library"; "Music"; "Pictures"; "Movies"; "Documents"] in
  let exclude_clause =
    List.concat_map (fun d -> ["-path"; Filename.concat root d; "-o"]) exclude_dirs
  in
  let exclude_clause = match List.rev exclude_clause with
    | "-o" :: rest -> List.rev rest
    | _ -> exclude_clause
  in
  let argv = Array.of_list (
    ["find"; root;
     "-type"; "d"; "-path"; "*/.*"; "-prune"; "-o";
     "-type"; "d"; "("] @ exclude_clause @ [")"; "-prune"; "-o";
     "-type"; "f"; "-name"; ".todo*"; "-print"]
  ) in
  try
    let ic = Unix.open_process_args_in "/usr/bin/find" argv in
    let rec loop acc =
      match input_line ic with
      | line -> loop (line :: acc)
      | exception End_of_file -> List.rev acc
    in
    let lines = loop [] in
    ignore (Unix.close_process_in ic);
    lines
  with _ -> []

let projects () =
  match Sys.getenv_opt "HOME" with
  | None -> Ok []
  | Some home -> Ok (find_todos home)

let now () =
  let tm = Unix.localtime (Unix.gettimeofday ()) in
  Printf.sprintf "%04d%02d%02d%02d%02d"
    (tm.Unix.tm_year + 1900)
    (tm.Unix.tm_mon + 1)
    tm.Unix.tm_mday
    tm.Unix.tm_hour
    tm.Unix.tm_min

let fx () = {
  projects = projects;
  read = read_lines;
  write = write_lines;
  now = now;
  editor = editor;
  commit = commit;
  get_repo = get_repo;
}

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
		let* _ = T.commit line path done_path editing effects in
		Ok ""
	| Echo (path, line) ->
		let* todos = list path effects in
		begin match List.nth_opt todos (line - 1) with
		| Some todo -> Ok todo
		| None -> Error (`WrongLine line)
		end
	| EditFile path -> Ok "@todo: edit file"
	| Doing (path, line) -> Ok "@todo: doing"
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
  let args = Array.to_list Sys.argv in
  let cli_args = match args with [] -> [] | _::tl -> tl in
  let effects = (fx()) in
  let todo_path = get_todo_path() in
  let done_path = get_done_path() in
  match command_router todo_path cli_args effects with
  | Some cmd ->
  		begin match (dispatch cmd todo_path done_path effects) with
    	| Ok "" -> ()
    	| Ok msg -> print_endline msg
      | Error (`NoRepository) -> print_endline "No repository found";
      | Error (`CommitError msg) -> print_endline ("Commit failed: " ^ msg);
      | Error (`FileSystem) -> print_endline "Filesystem error";
      | Error (`Editor) -> print_endline "Editor error";
      | Error (`WrongLine n) -> print_endline (Printf.sprintf "No todo at line %d" n);
      end
  | None -> print_endline "@todo: none"
