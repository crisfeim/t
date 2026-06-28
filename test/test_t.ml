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

type repo = { path: path; system: string }

type effects = {
  projects: unit -> (path list, [ `FileSystem ]) result;
  read    : path -> (string list, [ `FileSystem ]) result;
  write   : todo list -> path -> (unit, [ `FileSystem ]) result;
  now     : unit -> string;
  editor  : content -> (string, [ `Editor ]) result;
  commit  : message -> repo -> (unit, error) result;
  get_repo: path -> repo option
}

let ( let* )
  (x : ('a, [< error]) result)
  (f : 'a -> ('b, [> error]) result) : ('b, error) result =
  match x with
  | Ok v -> f v
  | Error e -> Error (e :> error)

let list todo_path effects =
  let* todos = effects.read todo_path in
  let formatted = todos |> List.mapi (fun idx content -> string_of_int (idx + 1) ^ " " ^ content) in
  Ok formatted

let add todo todo_path effects =
  let* todos = effects.read todo_path in
  let updated = todos @ [todo] in
  let* _ = effects.write updated todo_path in
  Ok ()

let extract line todo_path read =
  let* todos = read todo_path in
  if line < 1 || line > List.length todos then Error (`WrongLine line) else
  let updated = todos |> List.filteri (fun idx _ -> idx <> line - 1) in
  let extracted = List.nth todos (line - 1) in
  Ok (todos, extracted, updated)

let remove line todo_path effects =
  let* (_, _, updated) = extract line todo_path effects.read in
  let* _ = effects.write updated todo_path in
  Ok updated

let complete line todo_path done_path effects =
  let* (_, todo, updated) = extract line todo_path effects.read in
  let* done_todos = effects.read done_path in
  let done_formated = effects.now () ^ " " ^ todo in
  let* _ = effects.write (done_formated :: done_todos) done_path in
  let* _ = effects.write updated todo_path in
  Ok updated

let commit line todo_path done_path effects =
  let* repo =
    match effects.get_repo todo_path with
    | Some info -> Ok info
    | None -> Error `NoRepository
  in
  let* (todos, todo, updated) = extract line todo_path effects.read in
  let* msg = effects.editor todo in
  if msg = "" then Error (`CommitError "Commit aborted due to empty message") else
  let* _ = effects.commit msg repo in
  let* done_todos = effects.read done_path in
  let done_formatted = effects.now () ^ " " ^ msg in
  let* _ = effects.write (done_formatted :: done_todos) done_path in
  let* _ = effects.write updated todo_path in
  Ok ()

let projects effects =
  let* paths = effects.projects () in
  Ok paths

let edit line todo_path effects =
  let* (todos, todo, _) = extract line todo_path effects.read in
  let* edited = effects.editor todo in
  if edited = "" || edited = todo then Ok () else
  let updated = todos |> List.mapi (fun idx content -> if idx = line - 1 then edited else content) in
  let* _ = effects.write updated todo_path in
  Ok ()

(* Test helpers *)
let any_read     = (fun _ -> Ok [])
let any_write    = (fun _ _ -> Ok ())
let any_now      = (fun _ -> "any date")
let any_editor   = (fun _ -> Ok "")
let any_commit   = (fun _ _ -> Ok ())
let any_repo     = Some { path = "any repo dir"; system = "fossil" }
let any_projects = (fun () -> Ok ["any project path"])

let effects () = {
  projects = any_projects;
  read     = any_read;
  write    = any_write;
  now      = any_now;
  editor   = any_editor;
  commit   = any_commit;
  get_repo = (fun _ -> any_repo);
}

(* Generic helpers *)
let to_res v = function `Ok -> Ok v | #error as e -> Error (e :> error)
let to_unit = to_res ()

let read_res = function `Ok xs -> Ok xs | `FileSystem -> Error `FileSystem
let write_res = function `Ok -> Ok () | `FileSystem -> Error `FileSystem
let editor_res = function `Ok s -> Ok s | `Editor -> Error `Editor

let ((*List*)) =
  [ (`FileSystem, `FileSystem)
  ; (`Ok ["compra"; "lavar"], `Ok ["1 compra"; "2 lavar"])
  ]
  |> List.iter (fun (read_in, expected_in) ->
    assert (list "any todo path" {
      (effects ()) with read = (fun _ -> read_res read_in)
    } = read_res expected_in))

let ((*Add*)) =
  [ (`FileSystem, `Ok, `FileSystem)
  ; (`Ok [], `FileSystem, `FileSystem)
  ; (`Ok [], `Ok, `Ok)
  ]
  |> List.iter (fun (read_in, write_in, expected_in) ->
    assert (add "any todo" "any todo path" {
      (effects ()) with
      read = (fun _ -> read_res read_in);
      write = (fun _ _ -> write_res write_in);
    } = to_unit expected_in))

let ((*Remove*)) =
  [ (`FileSystem, 1, `Ok, `FileSystem)
  ; (`Ok ["any todo"], 2, `Ok, `WrongLine 2)
  ; (`Ok ["any todo"], 1, `FileSystem, `FileSystem)
  ; (`Ok ["any todo"], 1, `Ok, `Ok)
  ]
  |> List.iter (fun (read_in, line, write_in, expected_in) ->
    assert (remove line "any todo path" {
      (effects ()) with
      read = (fun _ -> read_res read_in);
      write = (fun _ _ -> write_res write_in);
    } = to_res [] expected_in))

let ((*Complete*)) =
  [ (`FileSystem, 1, `Ok, `FileSystem)
  ; (`Ok ["any todo"], 2, `Ok, `WrongLine 2)
  ; (`Ok ["any todo"], 1, `FileSystem, `FileSystem)
  ; (`Ok ["any todo"], 1, `Ok, `Ok)
  ]
  |> List.iter (fun (read_in, line, write_in, expected_in) ->
    assert (complete line "any todo path" "any done path" {
      (effects ()) with
      read = (fun _ -> read_res read_in);
      write = (fun _ _ -> write_res write_in);
    } = to_res [] expected_in))

let ((* Complete writes to done_path before updating todo_path *)) =
  let write_calls = ref [] in
  let _ = complete 1 "any todo path" "any done path" {
    (effects ()) with
    read = (fun path -> if path = "any done path" then Ok [] else Ok ["tarea"]);
    write = (fun data path -> write_calls := !write_calls @ [(path, data)]; Ok ());
    now = (fun () -> "202606252301");
  } in
  assert (!write_calls = [
    ("any done path", ["202606252301 tarea"]);
    ("any todo path", [])
  ])

let ((*Edit*)) =
  [ (`FileSystem, 1, `Ok "any edition", `Ok, `FileSystem)
  ; (`Ok ["any todo"], 2, `Ok "any edition", `Ok, `WrongLine 2)
  ; (`Ok ["any todo"], 1, `Editor, `Ok, `Editor)
  ; (`Ok ["any todo"], 1, `Ok "any edition", `FileSystem, `FileSystem)
  ; (`Ok ["any todo"], 1, `Ok "any edition", `Ok, `Ok)
  ]
  |> List.iter (fun (read_in, line, editor_in, write_in, expected_in) ->
    assert (edit line "any todo path" {
      (effects ()) with
      read = (fun _ -> read_res read_in);
      write = (fun _ _ -> write_res write_in);
      editor = (fun _ -> editor_res editor_in);
    } = to_unit expected_in))

let ((* Edit writes edited data *)) =
  let write_calls = ref [] in
  let _ = edit 1 "any todo path" {
    (effects ()) with
    read = (fun _ -> Ok ["todo"]);
    write = (fun todos _ -> write_calls := todos :: !write_calls; Ok ());
    editor = (fun _ -> Ok "edited");
  } in
  assert (!write_calls = [["edited"]])

let ((* Edit avoids unnecessary I/O when no changes or empty *)) =
  let assertion edited original =
    let did_wrote = ref false in
    let _ = edit 1 "any todo path" {
      (effects ()) with
      read = (fun _ -> Ok [original]);
      write = (fun _ _ -> did_wrote := true; Ok ());
      editor = (fun _ -> Ok edited);
    } in
    assert (!did_wrote = false)
  in
  assertion "" "original";
  assertion "original" "original"

let ((*Commit*)) =
  [ (None, `Ok ["any todo"], 1, `Ok "any msg", `Ok, `Ok, `NoRepository)
  ; (any_repo, `FileSystem, 1, `Ok "any msg", `Ok, `Ok, `FileSystem)
  ; (any_repo, `Ok ["any todo"], 2, `Ok "any msg", `Ok, `Ok, `WrongLine 2)
  ; (any_repo, `Ok ["any todo"], 1, `Editor, `Ok, `Ok, `Editor)
  ; (any_repo, `Ok ["any todo"], 1, `Ok "", `Ok, `Ok, `CommitError "Commit aborted due to empty message")
  ; (any_repo, `Ok ["any todo"], 1, `Ok "any msg", `CommitError "any error_msg", `Ok, `CommitError "any error_msg")
  ; (any_repo, `Ok ["any todo"], 1, `Ok "any msg", `Ok, `FileSystem, `FileSystem)
  ; (any_repo, `Ok ["any todo"], 1, `Ok "any msg", `Ok, `Ok, `Ok)
  ]
  |> List.iter (fun (repo, read_in, line, editor_in, commit_in, write_in, expected_in) ->
    assert (commit line "any todo path" "any done path" {
      (effects ()) with
      read = (fun _ -> read_res read_in);
      write = (fun _ _ -> write_res write_in);
      editor = (fun _ -> editor_res editor_in);
      commit = (fun _ _ -> match commit_in with `Ok -> Ok () | #error as e -> Error (e :> error));
      get_repo = (fun _ -> repo);
    } = to_unit expected_in))

let ((* Run commit archives todo in correct order on success *)) =
  let write_calls = ref [] in
  let _ = commit 1 "any todo path" "any done path" {
    (effects ()) with
    read = (fun path -> if path = "any done path" then Ok ["20260625 some"] else Ok ["todo"]);
    write = (fun data path -> write_calls := !write_calls @ [(path, data)]; Ok ());
    now = (fun () -> "20260627");
    editor = (fun _ -> Ok "edited");
    get_repo = (fun _ -> any_repo);
  } in
  assert (!write_calls = [
    ("any done path", ["20260627 edited"; "20260625 some"]);
    ("any todo path", [])
  ])

let ((*Projects*)) =
  [ (`FileSystem, `FileSystem)
  ; (`Ok ["p1"; "p2"], `Ok ["p1"; "p2"])
  ]
  |> List.iter (fun (projects_in, expected_in) ->
    assert (projects {
      (effects ()) with projects = (fun () -> read_res projects_in)
    } = read_res expected_in))
