let cwd filename =
  let current_dir = Sys.getcwd () in
  Filename.concat current_dir filename

let drop_first list = match list with [] -> [] | _::tl -> tl
