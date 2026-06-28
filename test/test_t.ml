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
	(* [< error] = at least a subensemble of my global error*)
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
	Ok()

let extract line todo_path read =
	let* todos = read todo_path in
	if line < 1 || line > List.length todos then Error (`WrongLine line) else
	let updated = todos |> List.filteri (fun idx _ -> idx <> line - 1) in
	let extracted = List.nth todos (line - 1) in
	Ok(todos, extracted, updated)

let remove line todo_path effects =
  let* (_, _, updated) = extract line todo_path effects.read in
	let* _ = effects.write updated todo_path in
	Ok updated

let complete line todo_path done_path effects =
	let* (_, todo, updated) = extract line todo_path effects.read in
	let* done_todos = effects.read done_path in
	let done_formated = effects.now() ^ " " ^ todo in
	let* _ = effects.write (done_formated :: done_todos) done_path in
	let* _ = effects.write updated todo_path in
	Ok updated

let (let*?) opt err =
	match opt with
	| Some v -> Ok v
	| None -> err

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

(* Test helpers *)
let any_read     = (fun _ -> Ok [])
let any_write    = (fun _ _ -> Ok())
let any_now      = (fun _ -> "any date")
let any_editor   = (fun _ -> Ok "")
let any_commit   = (fun _ _ -> Ok ())
let any_repo     = Some { path = "any repo dir" ; system = "fossil" }
let any_get_repo = (fun _ -> any_repo)
let any_projects = (fun () -> Ok ["any project path"])

let effects () = {
	projects = any_projects;
	read     = any_read;
	write    = any_write;
	now      = any_now;
	editor   = any_editor;
	commit   = any_commit;
	get_repo = any_get_repo;
}

let ((*List*)) =
	[
	  (Error `FileSystem, Error `FileSystem);
	  (Ok ["compra"; "lavar"], Ok ["1 compra"; "2 lavar"] )
	]
	|> List.iter (fun (read, expected) ->
			assert (list "any todo path" { (effects()) with read = (fun _ -> read) } = expected)
  )

let ((*Add*)) =
	[
		(Error `FileSystem, Ok()             , Error `FileSystem);
		(Ok[]             , Error `FileSystem, Error `FileSystem);
		(Ok[]						  , Ok()					   , Ok())
	] |> List.iter (fun (read, write, expected) ->
		assert (add "any todo" "any todo path" {
			(effects()) with
			read 	 = (fun _ -> read);
			write  = (fun _ _ -> write);
		} = expected)
	)

let ((*Remove*)) =
	[
		(Error `FileSystem , 1 , Ok() 					  , Error `FileSystem);
		(Ok ["any todo"]   , 2 , Ok()						  , Error (`WrongLine 2));
		(Ok ["any todo"]   , 1 , Error `FileSystem, Error `FileSystem);
		(Ok ["any todo"]   , 1 , Ok()             , Ok[])
	] |> List.iter (fun (read, line, write, expected) ->
		assert (remove line "any todo path" {
			(effects()) with
			read   = (fun _ -> read);
			write  = (fun _ _ -> write);
		} = expected)
	)

let ((*Complete*)) =
	[
		(Error `FileSystem, 1, Ok() 					  , Error `FileSystem);
		(Ok["any todo"]   , 2, Ok()				      , Error (`WrongLine 2));
		(Ok["any todo"]	  , 1, Error `FileSystem, Error `FileSystem);
		(Ok["any todo"]	  , 1, Ok()					  	, Ok[])
	] |> List.iter (fun (read, line, write, expected) ->
		assert (complete line "any todo path" "any done path" {
			(effects()) with
			read   = (fun _ -> read);
			write  = (fun _ _ -> write);
		} = expected)
	)

let ((* Complete writes to done_path before updating todo_path *)) =
  let write_calls = ref [] in

  let _ = complete 1 "any todo path" "any done path" {
 		(effects()) with
    read   = (fun path -> if path = "any done path" then Ok[] else Ok ["tarea"]);
    write  = (fun data path -> write_calls := !write_calls @ [(path, data)]; Ok ());
    now    = (fun () -> "202606252301");
  }  in

  assert (!write_calls = [
  	("any done path", ["202606252301 tarea"]);
    ("any todo path", [])
  ])


let edit line todo_path effects =
	let* (todos, todo, _) = extract line todo_path effects.read in
	let* edited = effects.editor todo in
	if edited = "" || edited = todo then Ok() else
	let updated = todos |> List.mapi (fun idx content -> if idx = line - 1 then edited else content) in
	let* _ = effects.write updated todo_path in
	Ok()

let ((*Edit*)) =
	[
		(Error `FileSystem, 1, Ok "any edition" , Ok()             , Error `FileSystem);
		(Ok ["any todo"]  , 2, Ok "any edition" , Ok()             , Error (`WrongLine 2));
		(Ok ["any todo"]  , 1, Error `Editor    , Ok()             , Error `Editor);
		(Ok ["any todo"]  , 1, Ok "any edition" , Error `FileSystem, Error `FileSystem);
		(Ok ["any todo"]  , 1, Ok "any edition" , Ok()             , Ok())
	] |> List.iter (fun (read, line, editor, write, expected) ->
		assert (edit line "any todo path" {
			(effects()) with
			read   = (fun _ -> read);
			write  = (fun _ _ -> write);
			editor = (fun _ -> editor);
		} = expected)
	)


let ((* Edit writes edited data *)) =
	let write_calls = ref [] in
	let _ = edit 1 "any todo path" {
		(effects()) with
		read = (fun _ -> Ok ["todo"]);
		write = (fun todos _ -> write_calls := todos :: !write_calls; Ok());
		editor = (fun _ -> Ok "edited");
	} in

	assert (!write_calls = [["edited"]])

let ((* Edit avoids unnecessary I/O when no changes or empty *)) =
	let assertion edited original =
		let did_wrote = ref false in
		let _ = edit 1 "any todo path" {
			(effects()) with
			read   = (fun _ -> Ok [original]);
			write  = (fun todos _ -> did_wrote := true ; Ok());
			editor = (fun _ -> Ok edited);
		} in

		assert (!did_wrote = false) in

	assertion ""         "original" ;
	assertion "original" "original"

let ((*Commit*)) =
[
(None     , Ok ["todo"]      , 1, Ok "msg"      , Ok ()                           , Ok ()            , Error `NoRepository );
(any_repo , Error `FileSystem, 1, Ok "msg"      , Ok ()                           , Ok ()            , Error `FileSystem);
(any_repo , Ok ["todo"] 		 , 2, Ok "msg"      , Ok ()                           , Ok ()            , Error (`WrongLine 2));
(any_repo , Ok ["todo"] 		 , 1, Error `Editor , Ok ()                           , Ok ()            , Error `Editor);
(any_repo , Ok ["todo"]	     , 1, Ok ""         , Ok ()                           , Ok ()            , Error (`CommitError "Commit aborted due to empty message"));
(any_repo , Ok ["todo"]      , 1, Ok "msg"      , Error (`CommitError "any error"), Ok ()            , Error (`CommitError "any error"));
(any_repo , Ok ["todo"]      , 1, Ok "msg"      , Ok ()                           , Error `FileSystem, Error `FileSystem);
(any_repo , Ok ["todo"]      , 1, Ok "edited"   , Ok ()                           , Ok ()            , Ok ())
] |> List.iter (fun (repo, read, line, editor, commit_r, write, expected) ->
		assert (commit line "any todo path" "any done path" {
			(effects()) with
			read     = (fun _ -> read);
			write    = (fun _ _ -> write);
			editor   = (fun _ -> editor);
			commit   = (fun _ _ -> commit_r);
			get_repo = (fun _ -> repo)
		} = expected)
	)

let ((* Run commit archives todo in correct order on success *)) =
	let write_calls = ref [] in
	let _ = commit 1 "any todo path" "any done path" {
		(effects()) with
		read     = (fun path -> if path = "any done path" then Ok ["20260625 some"] else Ok ["todo"]);
		write    = (fun data path -> write_calls := !write_calls @ [(path, data)]; Ok ());
		now      = (fun () -> "20260627");
		editor   = (fun _ -> Ok "edited");
		get_repo = (fun _ -> any_repo)
	} in

	assert (!write_calls = [
		("any done path", ["20260627 edited"; "20260625 some"]);
		("any todo path", [])
	])

let ((*Run commit uses editor output as commit message *)) =
  let commit_msg = ref "" in
  let _ = commit 1 "any todo path" "any done path" {
    (effects()) with
    read     = (fun path -> if path = "any done path" then Ok [] else Ok ["todo"]);
    editor   = (fun _ -> Ok "edited");
    commit   = (fun msg _ -> commit_msg := msg; Ok ());
    get_repo = (fun _ -> any_repo);
  } in
  assert (!commit_msg = "edited")

let ((*Projects*)) =
	[
		(Error `FileSystem, Error `FileSystem);
		(Ok ["p1"; "p2"]  , Ok ["p1"; "p2"]  )
	] |> List.iter (fun (projects_r, expected) ->
		assert (projects { (effects()) with projects = (fun () -> projects_r);} = expected))
