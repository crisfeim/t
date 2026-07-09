type error =
  [ `FileSystem
  | `WrongLine of int
  | `Editor
  | `NoRepository
  | `CommitError of string
  ]

type todo = string
type path = string
type content = string
type message = string

type repo =
  { path : path
  ; system : string
  }

type effects =
  { projects : unit -> (path list, [ `FileSystem ]) result
  ; read : path -> (string list, [ `FileSystem ]) result
  ; write : todo list -> path -> (unit, [ `FileSystem ]) result
  ; now : unit -> string
  ; editor : content -> (string, [ `Editor ]) result
  ; commit : message -> repo -> (unit, error) result
  ; get_repo : path -> repo option
  }

let ( let* ) (x : ('a, [< error ]) result) (f : 'a -> ('b, [> error ]) result)
  : ('b, error) result
  =
  match x with
  | Ok v -> f v
  | Error e -> Error (e :> error)
;;

let list todo_path effects =
  let* todos = effects.read todo_path in
  let formatted =
    todos
    |> List.rev
    |> List.mapi (fun idx content -> string_of_int (idx + 1) ^ " " ^ content)
  in
  Ok formatted
;;

let add todo todo_path effects =
  let* todos = effects.read todo_path in
  let updated = todos @ [ todo ] in
  let* _ = effects.write updated todo_path in
  Ok todo
;;

let extract line todo_path read =
  let* todos = read todo_path in
  if line < 1 || line > List.length todos
  then Error (`WrongLine line)
  else (
    let updated = todos |> List.filteri (fun idx _ -> idx <> line - 1) in
    let extracted = List.nth todos (line - 1) in
    Ok (todos, extracted, updated))
;;

let remove line todo_path effects =
  let* _, removed, updated = extract line todo_path effects.read in
  let* _ = effects.write updated todo_path in
  Ok removed
;;

let complete line todo_path done_path effects =
  let* _, todo, updated = extract line todo_path effects.read in
  let* done_todos = effects.read done_path in
  let done_formated = effects.now () ^ " " ^ todo in
  let* _ = effects.write (done_formated :: done_todos) done_path in
  let* _ = effects.write updated todo_path in
  Ok todo
;;

let commit line todo_path done_path open_editor effects =
  let* repo =
    match effects.get_repo todo_path with
    | Some info -> Ok info
    | None -> Error `NoRepository
  in
  let* todos, todo, updated = extract line todo_path effects.read in
  let* msg =
    if open_editor
    then
      let* edited = effects.editor todo in
      if edited = ""
      then Error (`CommitError "Commit aborted due to empty message")
      else Ok edited
    else Ok todo
  in
  let* _ = effects.commit msg repo in
  let* done_todos = effects.read done_path in
  let done_formatted = effects.now () ^ " " ^ msg in
  let* _ = effects.write (done_formatted :: done_todos) done_path in
  let* _ = effects.write updated todo_path in
  Ok ()
;;

let projects effects = effects.projects ()

let edit line todo_path effects =
  let* todos, todo, _ = extract line todo_path effects.read in
  let* edited = effects.editor todo in
  if edited = "" || edited = todo
  then Ok ()
  else (
    let updated =
      todos |> List.mapi (fun idx content -> if idx = line - 1 then edited else content)
    in
    let* _ = effects.write updated todo_path in
    Ok ())
;;

let sort_matches projects =
  List.sort
    (fun path1 path2 ->
       let count1 = List.length (String.split_on_char '/' path1) in
       let count2 = List.length (String.split_on_char '/' path2) in
       if count1 <> count2
       then compare count1 count2
       else (
         let len1 = String.length path1 in
         let len2 = String.length path2 in
         if len1 <> len2 then compare len1 len2 else String.compare path1 path2))
    projects
;;

let project name effects =
  let* projects = projects effects in
  match
    projects
    |> sort_matches
    |> List.find_opt (fun path -> List.mem name (String.split_on_char '/' path))
  with
  | Some found_path -> list found_path effects
  | None -> Error `FileSystem
;;
