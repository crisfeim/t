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


(* List *)
let () =
	[
	  (Error FileSystem			 , Error FileSystem					);
	  (Ok ["compra"; "lavar"], Ok ["1 compra"; "2 lavar"])
	]
	|> List.iter (fun (read, expected) ->
			assert (list "any todo path" {
     		read   = (fun _ -> read);
      	write  = (fun _ _ -> Ok ());
        now    = (fun _ -> "any date");
        editor = (fun _ -> Ok "")
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
		assert (add "any todo path" "any done path" {
			read 	 = (fun _ -> read);
			write  = (fun _ _ -> write);
			now    = (fun _ -> "any date");
		  editor = (fun _ -> Ok "")
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
		assert (remove line "todo path" {
			read   = (fun _ -> read);
			write  = (fun _ _ -> write);
			now    = (fun _ -> "any date");
			editor = (fun _ -> Ok "")
		} = expected)
	)

(* Complete *)
let () =
	[
		(Error FileSystem, 1, Ok() 						, Error FileSystem	 );
		(Ok["todo"]      , 2, Ok()				    , Error (WrongLine 2));
		(Ok["todo"]			 , 1, Error FileSystem, Error FileSystem	 );
		(Ok["todo"]			 , 1, Ok()						, Ok[]							 )
	] |> List.iter (fun (read, line, write, expected) ->
		assert (complete line "todo path" "done path" {
			read   = (fun _ -> read);
			write  = (fun _ _ -> write);
			now    = (fun _ -> "any date");
			editor = (fun _ -> Ok "")
		} = expected)
	)

(* Complete writes to done_path before updating todo_path *)
let () =
  let history = ref [] in

  let _ = complete 1 "todo_path" "done_path" {
    read   = (fun path -> if path = "done_path" then Ok[] else Ok ["tarea"]);
    write  = (fun data path -> history := !history @ [(path, data)]; Ok ());
    now    = (fun () -> "202606252301");
    editor = (fun _ -> Ok "")
  }  in

  assert (!history = [
    ("done_path", ["202606252301 tarea"]);
    ("todo_path", [])
  ])

let edit line todo_path effects =
	let* (todos, todo, updated) = extract line todo_path effects.read in
	let* edited = effects.editor todo in
	if edited = "" || edited = todo then Ok() else
	let updated = todos |> List.mapi (fun idx content -> if idx = line - 1 then edited else content) in
	let* _ = effects.write updated todo_path in
	Ok()

(* Edit *)
let () =
	[
		(Error FileSystem, 1, Ok "edited" , Ok()            , Error FileSystem   );
		(Ok ["any todo"] , 2, Ok "edited" , Ok()            , Error (WrongLine 2));
		(Ok ["any todo"] , 1, Error Editor, Ok()            , Error Editor       );
		(Ok ["any todo"] , 1, Ok "edited" , Error FileSystem, Error FileSystem   );
		(Ok ["any todo"] , 1, Ok "edited" , Ok()            , Ok()               )
	] |> List.iter (fun (read, line, editor, write, expected) ->
		assert (edit line "todo path" {
			read   = (fun _ -> read);
			write  = (fun _ _ -> write);
			now    = (fun () -> "any date");
			editor = (fun _ -> editor)
		} = expected)
	)

(* Edit writes edited data *)
let () =
	let history = ref "" in
	let _ = edit 1 "todo path" {
		read = (fun _ -> Ok ["todo"]);
		write = (fun todos _ -> history := List.nth todos (0); Ok());
		now = (fun () -> "any date");
		editor = (fun _ -> Ok "edited")
	} in

	assert (!history = "edited")

(* Edit avoids unnecessary I/O when no changes or empty *)
let () =
	let assertion edited original =
		let did_wrote = ref false in
		let _ = edit 1 "todo path" {
			read = (fun _ -> Ok [original]);
			write = (fun todos _ -> did_wrote := true ; Ok());
			now = (fun () -> "any date");
			editor = (fun _ -> Ok edited)
		} in

		assert (!did_wrote = false) in

	assertion "" "original" ;
	assertion "original" "original"
