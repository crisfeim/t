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

let fx () = {
  projects = (fun _ -> Ok []);
  read = read_lines;
  write = write_lines;
  now = (fun _ -> "@todo:formatted date");
  editor = (fun _ -> Ok "");
  commit = (fun _ _ -> Ok ());
  get_repo = (fun _ -> None);
}

let get_todo_path () =
  let current_dir = Sys.getcwd () in
  Filename.concat current_dir ".todo"

let get_done_path () =
  let current_dir = Sys.getcwd () in
  Filename.concat current_dir ".done"

let () =
  let args = Array.to_list Sys.argv in
  let cli_args = match args with [] -> [] | _::tl -> tl in
  let effects = (fx()) in
  let todo_path = get_todo_path() in
  let done_path = get_done_path() in
  match command_router todo_path cli_args effects with
  | Some cmd ->
      begin match cmd with
      | Count -> begin match (list todo_path effects) with
      	| Ok todos -> print_endline (string_of_int (List.length todos))
        | Error _ -> print_endline "Error"
        end
      | List path -> begin match (list path effects) with
      	| Ok todos -> List.iter (fun todo -> print_endline todo) todos
      	| Error _ -> print_endline "Error"
       	end
      | ListRange (path, range) -> begin match (list path effects) with
      	|	Ok todos -> todos |> List.filteri (fun i _ -> List.mem (i + 1) range)
       		|> List.iter (fun todo -> print_endline todo)
       	| Error _ -> print_endline "Error"
      	end
      | Add (path, todo) -> begin match (add todo path effects) with
      	| Ok todo -> print_endline todo
        | Error _ -> print_endline "Error"
      	end
      | Complete (path, lines) -> begin match (complete (List.hd lines) path done_path effects) with
      	| Ok todo -> print_endline todo
       	| Error _ -> print_endline "Error"
       end
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
