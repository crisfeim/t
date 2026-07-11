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

let fx () = {
  projects = (fun _ -> Ok []);
  read = read_lines;
  write = (fun _ _ -> Ok ());
  now = (fun _ -> "@todo:formatted date");
  editor = (fun _ -> Ok "");
  commit = (fun _ _ -> Ok ());
  get_repo = (fun _ -> None);
}

let get_todo_path () =
  let current_dir = Sys.getcwd () in
  Filename.concat current_dir ".todo"


let () =
  let args = Array.to_list Sys.argv in
  let cli_args = match args with [] -> [] | _::tl -> tl in
  let effects = (fx()) in
  match command_router (get_todo_path()) cli_args effects with
  | Some cmd ->
      begin match cmd with
      | Count -> print_endline "@todo: count"
      | List path -> begin match (list path effects) with
      	| Ok todos -> List.iter (fun todo -> print_endline todo) todos
      	| Error _ -> print_endline "Error"
       end
      | ListRange (path, line) -> print_endline "@todo: list range"
      | Add (path, todo) -> print_endline "@todo: add"
      | Complete (path, line) -> print_endline "@todo: complete"
      | Remove (path, line) -> print_endline "@todo: remove"
      | Edit (path, line) -> print_endline "@todo: edit"
      | Commit (path, line, msg) -> print_endline "@todo: commit"
      | Echo (path, line) -> print_endline "@todo: echo"
      | EditFile path -> print_endline "@todo: edit file"
      | Doing (path, line) -> print_endline "@todo: doing"
      | ListDoing path -> print_endline "@todo: list doing"
      | ListProjects -> print_endline "@todo: list projects"
      | ListDoingAcrossProjects -> print_endline "@todo: list doing across projects"
      end
  | None -> print_endline "@todo: none"
