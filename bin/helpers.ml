let cwd filename =
  let current_dir = Sys.getcwd () in
  Filename.concat current_dir filename
