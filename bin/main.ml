let () =
  let args = Array.to_list Sys.argv in
  match args with
  | [] | [_] -> print_endline ""
  | _ :: actual_args -> print_endline (String.concat " " actual_args)
