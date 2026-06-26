type error =
	| FileSystem
	| WrongLine of int
	| Editor

type todo    = string
type path    = string
type content = string

type effects = {
	read   : path -> (string list, error) result;
	write  : todo list -> path -> (unit, error) result;
	now    : unit -> string;
	editor : content -> (string, error) result
}

let ( let* ) = Result.bind

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
	if line < 1 || line > List.length todos then Error (WrongLine line) else
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

(* Test helpers *)
let any_write  = (fun _ _ -> Ok())
let any_now    = (fun _ -> "any date")
let any_editor = (fun _ -> Ok "")

(* List *)
let () =
	[
	  (Error FileSystem			 , Error FileSystem					);
	  (Ok ["compra"; "lavar"], Ok ["1 compra"; "2 lavar"])
	]
	|> List.iter (fun (read, expected) ->
			assert (list "any todo path" {
     		read   = (fun _ -> read);
      	write  = any_write;
        now    = any_now;
        editor = any_editor
   			} = expected
			)
  )

(* Add *)
let () =
	[
		(Error FileSystem, Ok()            , Error FileSystem);
		(Ok[]            , Error FileSystem, Error FileSystem);
		(Ok[]						 , Ok()					   , Ok()            )
	] |> List.iter (fun (read, write, expected) ->
		assert (add "any todo" "any todo path" {
			read 	 = (fun _ -> read);
			write  = (fun _ _ -> write);
      now    = any_now;
      editor = any_editor
		} = expected)
	)

(* Remove *)
let () =
	[
		(Error FileSystem  , 1 , Ok() 					 , Error FileSystem   );
		(Ok ["any todo"]   , 2 , Ok()						 , Error (WrongLine 2));
		(Ok ["any todo"]   , 1 , Error FileSystem, Error FileSystem		);
		(Ok ["any todo"]   , 1 , Ok()            , Ok[] 							)
	] |> List.iter (fun (read, line, write, expected) ->
		assert (remove line "any todo path" {
			read   = (fun _ -> read);
			write  = (fun _ _ -> write);
			now    = any_now;
			editor = any_editor
		} = expected)
	)

(* Complete *)
let () =
	[
		(Error FileSystem, 1, Ok() 						, Error FileSystem	 );
		(Ok["any todo"]  , 2, Ok()				    , Error (WrongLine 2));
		(Ok["any todo"]	 , 1, Error FileSystem, Error FileSystem	 );
		(Ok["any todo"]	 , 1, Ok()						, Ok[]							 )
	] |> List.iter (fun (read, line, write, expected) ->
		assert (complete line "any todo path" "any done path" {
			read   = (fun _ -> read);
			write  = (fun _ _ -> write);
			now    = any_now;
			editor = any_editor
		} = expected)
	)

(* Complete writes to done_path before updating todo_path *)
let () =
  let history = ref [] in

  let _ = complete 1 "any todo path" "any done path" {
    read   = (fun path -> if path = "any done path" then Ok[] else Ok ["tarea"]);
    write  = (fun data path -> history := !history @ [(path, data)]; Ok ());
    now    = (fun () -> "202606252301");
    editor = any_editor
  }  in

  assert (!history = [
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

(* Edit *)
let () =
	[
		(Error FileSystem, 1, Ok "any edition" , Ok()            , Error FileSystem   );
		(Ok ["any todo"] , 2, Ok "any edition" , Ok()            , Error (WrongLine 2));
		(Ok ["any todo"] , 1, Error Editor     , Ok()            , Error Editor       );
		(Ok ["any todo"] , 1, Ok "any edition" , Error FileSystem, Error FileSystem   );
		(Ok ["any todo"] , 1, Ok "any edition" , Ok()            , Ok()               )
	] |> List.iter (fun (read, line, editor, write, expected) ->
		assert (edit line "any todo path" {
			read   = (fun _ -> read);
			write  = (fun _ _ -> write);
			now    = any_now;
			editor = (fun _ -> editor)
		} = expected)
	)

(* Edit writes edited data *)
let () =
	let write_calls = ref [] in
	let _ = edit 1 "any todo path" {
		read = (fun _ -> Ok ["todo"]);
		write = (fun todos _ -> write_calls := todos :: !write_calls; Ok());
		now = any_now;
		editor = (fun _ -> Ok "edited")
	} in

	assert (!write_calls = [["edited"]])

(* Edit avoids unnecessary I/O when no changes or empty *)
let () =
	let assertion edited original =
		let did_wrote = ref false in
		let _ = edit 1 "any todo path" {
			read   = (fun _ -> Ok [original]);
			write  = (fun todos _ -> did_wrote := true ; Ok());
			now    = any_now;
			editor = (fun _ -> Ok edited)
		} in

		assert (!did_wrote = false) in

	assertion ""         "original" ;
	assertion "original" "original"
