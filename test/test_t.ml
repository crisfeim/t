type error =
	| FileSystem
	| WrongLine of int
	| Editor

type todo = string
type path = string

type effects = {
	read  : path -> (string list, error) result;
	write : todo list -> path -> (unit, error) result;
	now   : unit -> string
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

let extract line todo_path effects =
	let* todos = effects.read todo_path in
	if line < 1 || line > List.length todos then Error (WrongLine line) else
	let updated = todos |> List.filteri (fun idx _ -> idx <> line - 1) in
	let extracted = List.nth todos (line - 1) in
	Ok(extracted, updated)

let remove line todo_path effects =
  let* (_, updated) = extract line todo_path effects in
	let* _ = effects.write updated todo_path in
	Ok updated

let complete line todo_path done_path effects =
	let* (todo, updated) = extract line todo_path effects in
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
     		read  = (fun _ -> read);
       	write = (fun _ _ -> Ok ());
        now   = (fun _ -> "any date")
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
			read 	= (fun _ -> read);
			write = (fun _ _ -> write);
			now   = (fun _ -> "any date")
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
			read  = (fun _ -> read);
			write = (fun _ _ -> write);
			now   = (fun _ -> "any date")
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
			read  = (fun _ -> read);
			write = (fun _ _ -> write);
			now   = (fun _ -> "any date")
		} = expected)
	)

(* Complete writes to done_path before updating todo_path *)
let () =
  let history = ref [] in

  let _ = complete 1 "todo_path" "done_path" {
    read  = (fun path -> if path = "done_path" then Ok[] else Ok ["tarea"]);
    write = (fun data path -> history := !history @ [(path, data)]; Ok ());
    now   = (fun () -> "202606252301")
  }  in

  assert (!history = [
    ("done_path", ["202606252301 tarea"]);
    ("todo_path", [])
  ])

let edit line todo_path effects =
	let* todos = effects.read todo_path in
	if line < 1 || line > List.length todos then Error (WrongLine line) else
	Ok()

(* Edit *)
let () =
	[
		(Error FileSystem, 1, Ok(), Ok(), Error FileSystem);
		(Ok ["any todo"],  2, Ok(), Ok(), Error (WrongLine 2) )
	] |> List.iter (fun (read, line, editor, write, expected) ->
		assert (edit line "todo path" {
			read  = (fun _ -> read);
			write = (fun _ _ -> write);
			now   = (fun () -> "any date")
		} = expected)
	)
