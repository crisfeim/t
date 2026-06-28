type error =
	[
  | `FileSystem
  | `WrongLine of int
  | `Editor
  | `NoRepository
  | `CommitError of string
]

type todo    = string
type path    = string
type content = string
type message = string

type repo = { path: path; system: string }

type effects = {
	projects: unit -> (path list, [`FileSystem]) result;
	read    : path -> (string list, [`FileSystem]) result;
	write   : todo list -> path -> (unit, [`FileSystem]) result;
	now     : unit -> string;
	editor  : content -> (string, [`Editor]) result;
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
	Ok todo

let extract line todo_path read =
	let* todos = read todo_path in
	if line < 1 || line > List.length todos then Error (`WrongLine line) else
	let updated = todos |> List.filteri (fun idx _ -> idx <> line - 1) in
	let extracted = List.nth todos (line - 1) in
	Ok (todos, extracted, updated)

let remove line todo_path effects =
	let* (_, removed, updated) = extract line todo_path effects.read in
	let* _ = effects.write updated todo_path in
	Ok removed

let complete line todo_path done_path effects =
	let* (_, todo, updated) = extract line todo_path effects.read in
	let* done_todos = effects.read done_path in
	let done_formated = effects.now () ^ " " ^ todo in
	let* _ = effects.write (done_formated :: done_todos) done_path in
	let* _ = effects.write updated todo_path in
	Ok todo

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
let any_read = (fun _ -> Ok [])
let any_write = (fun _ _ -> Ok ())
let any_now = (fun _ -> "any date")
let any_editor = (fun _ -> Ok "")
let any_commit = (fun _ _ -> Ok ())
let any_repo = Some { path = "any repo dir"; system = "fossil" }
let any_projects = (fun () -> Ok ["any project path"])

let effects () = {
	projects = any_projects;
	read = any_read;
	write = any_write;
	now = any_now;
	editor = any_editor;
	commit = any_commit;
	get_repo = (fun _ -> any_repo);
}

(* Tests *)
open Test

let () = case "List" (fun test ->
  [ ("delivers error on read failure", Error `FileSystem, Error `FileSystem) ;
    ("formats todos with line numbers", Ok ["compra"; "lavar"], Ok ["1 compra"; "2 lavar"]) ;
  ] |> List.iter (fun (description, read, expected) ->
    test description (fun expect ->
      expect.equal expected
        (list "any todo path" { (effects ()) with read = (fun _ -> read) })
    ))
)

let () = case "Add" (fun test ->
  [ ("delivers error on read failure", Error `FileSystem, Ok (), Error `FileSystem) ;
    ("delivers error on write failure", Ok [], Error `FileSystem, Error `FileSystem) ;
    ("returns added todo on success", Ok [], Ok (), Ok "any todo") ;
  ] |> List.iter (fun (description, read, write, expected) ->
    test description (fun expect ->
      expect.equal expected
        (add "any todo" "any todo path" { (effects ()) with
          read = (fun _ -> read);
          write = (fun _ _ -> write); })
    ))
)

let () = case "Remove" (fun test ->
  [ ("delivers error on read failure", Error `FileSystem, 1, Ok (), Error `FileSystem) ;
    ("delivers error on wrong line", Ok ["any todo"], 2, Ok (), Error (`WrongLine 2)) ;
    ("delivers error on write failure", Ok ["any todo"], 1, Error `FileSystem, Error `FileSystem) ;
    ("returns removed todo on success", Ok ["any todo"], 1, Ok (), Ok "any todo") ;
  ] |> List.iter (fun (description, read, line, write, expected) ->
    test description (fun expect ->
      expect.equal expected
        (remove line "any todo path" { (effects ()) with
          read = (fun _ -> read);
          write = (fun _ _ -> write); })
    ))
)

let () = case "Complete" (fun test ->
  [ ("delivers error on read failure", Error `FileSystem, 1, Ok (), Error `FileSystem) ;
    ("delivers error on wrong line", Ok ["any todo"], 2, Ok (), Error (`WrongLine 2)) ;
    ("delivers error on write failure", Ok ["any todo"], 1, Error `FileSystem, Error `FileSystem) ;
    ("returns completed todo on success", Ok ["any todo"], 1, Ok (), Ok "any todo") ;
  ] |> List.iter (fun (description, read, line, write, expected) ->
    test description (fun expect ->
      expect.equal expected
        (complete line "any todo path" "any done path" { (effects ()) with
          read = (fun _ -> read);
          write = (fun _ _ -> write); })
    ));

  test "writes to done_path before updating todo_path" (fun expect ->
    let write_calls = ref [] in
    let _ = complete 1 "any todo path" "any done path" { (effects ()) with
      read = (fun path -> if path = "any done path" then Ok [] else Ok ["tarea"]);
      write = (fun data path -> write_calls := !write_calls @ [(path, data)]; Ok ());
      now = (fun () -> "202606252301");
    } in
    expect.equal
      [("any done path", ["202606252301 tarea"]); ("any todo path", [])]
      !write_calls
  )
)

let () = case "Edit" (fun test ->
  [ ("delivers error on read failure", Error `FileSystem, 1, Ok "any edition", Ok (), Error `FileSystem) ;
    ("delivers error on wrong line", Ok ["any todo"], 2, Ok "any edition", Ok (), Error (`WrongLine 2)) ;
    ("delivers error on editor failure", Ok ["any todo"], 1, Error `Editor, Ok (), Error `Editor) ;
    ("delivers error on write failure", Ok ["any todo"], 1, Ok "any edition", Error `FileSystem, Error `FileSystem) ;
    ("succeeds", Ok ["any todo"], 1, Ok "any edition", Ok (), Ok ()) ;
  ] |> List.iter (fun (description, read, line, editor, write, expected) ->
    test description (fun expect ->
      expect.equal expected
        (edit line "any todo path" { (effects ()) with
          read = (fun _ -> read);
          write = (fun _ _ -> write);
          editor = (fun _ -> editor); })
    ));

  test "writes edited data" (fun expect ->
    let write_calls = ref [] in
    let _ = edit 1 "any todo path" { (effects ()) with
      read = (fun _ -> Ok ["any todo"]);
      write = (fun todos _ -> write_calls := todos :: !write_calls; Ok ());
      editor = (fun _ -> Ok "edited");
    } in
    expect.equal [["edited"]] !write_calls
  );

  test "avoids unnecessary I/O when editor returns empty" (fun expect ->
    let did_write = ref false in
    let _ = edit 1 "any todo path" { (effects ()) with
      read = (fun _ -> Ok ["any todo"]);
      write = (fun _ _ -> did_write := true; Ok ());
      editor = (fun _ -> Ok "");
    } in
    expect.is (not !did_write) "expected no write"
  );

  test "avoids unnecessary I/O when editor returns unchanged" (fun expect ->
    let did_write = ref false in
    let _ = edit 1 "any todo path" { (effects ()) with
      read = (fun _ -> Ok ["any todo"]);
      write = (fun _ _ -> did_write := true; Ok ());
      editor = (fun _ -> Ok "any todo");
    } in
    expect.is (not !did_write) "expected no write"
  )
)

let () = case "Commit" (fun test ->
  [ ("delivers error on missing repo", None, Ok ["any todo"], 1, Ok "any edition", Ok (), Ok (), Error `NoRepository) ;
    ("delivers error on read failure", any_repo, Error `FileSystem, 1, Ok "any edition", Ok (), Ok (), Error `FileSystem) ;
    ("delivers error on wrong line", any_repo, Ok ["any todo"], 2, Ok "any edition", Ok (), Ok (), Error (`WrongLine 2)) ;
    ("delivers error on editor failure", any_repo, Ok ["any todo"], 1, Error `Editor, Ok (), Ok (), Error `Editor) ;
    ("delivers error on empty message", any_repo, Ok ["any todo"], 1, Ok "", Ok (), Ok (), Error (`CommitError "Commit aborted due to empty message")) ;
    ("delivers error on commit failure", any_repo, Ok ["any todo"], 1, Ok "any edition", Error (`CommitError "any error"), Ok (), Error (`CommitError "any error")) ;
    ("delivers error on write failure", any_repo, Ok ["any todo"], 1, Ok "any edition", Ok (), Error `FileSystem, Error `FileSystem) ;
    ("succeeds", any_repo, Ok ["any todo"], 1, Ok "any edition", Ok (), Ok (), Ok ()) ;
  ] |> List.iter (fun (description, repo, read, line, editor, commit_r, write, expected) ->
    test description (fun expect ->
      expect.equal expected
        (commit line "any todo path" "any done path" { (effects ()) with
          read = (fun _ -> read);
          write = (fun _ _ -> write);
          editor = (fun _ -> editor);
          commit = (fun _ _ -> commit_r);
          get_repo = (fun _ -> repo); })
    ));

  test "archives todo in correct order on success" (fun expect ->
    let write_calls = ref [] in
    let _ = commit 1 "any todo path" "any done path" { (effects ()) with
      read = (fun path -> if path = "any done path" then Ok ["20260625 some"] else Ok ["any todo"]);
      write = (fun data path -> write_calls := !write_calls @ [(path, data)]; Ok ());
      now = (fun () -> "20260627");
      editor = (fun _ -> Ok "edited");
      get_repo = (fun _ -> any_repo);
    } in
    expect.equal
      [("any done path", ["20260627 edited"; "20260625 some"]); ("any todo path", [])]
      !write_calls
  );

  test "uses editor output as commit message" (fun expect ->
    let commit_msg = ref "" in
    let _ = commit 1 "any todo path" "any done path" { (effects ()) with
      read = (fun path -> if path = "any done path" then Ok [] else Ok ["any todo"]);
      editor = (fun _ -> Ok "edited");
      commit = (fun msg _ -> commit_msg := msg; Ok ());
      get_repo = (fun _ -> any_repo);
    } in
    expect.equal "edited" !commit_msg
  )
)

let () = case "Projects" (fun test ->
  [ ("delivers error on filesystem failure", Error `FileSystem, Error `FileSystem) ;
    ("returns project paths on success", Ok ["p1"; "p2"], Ok ["p1"; "p2"]) ;
  ] |> List.iter (fun (description, projects_r, expected) ->
    test description (fun expect ->
      expect.equal expected
        (projects { (effects ()) with projects = (fun () -> projects_r) })
    ))
)
