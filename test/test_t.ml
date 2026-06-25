type error =
	| FileSystem
	| WrongLine of int

type todo = string
type path = string

type effects = {
	read : path -> (string list, error) result;
	write: todo list -> path -> (unit, error) result;
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

let remove line todo_path effects =
	let* todos = effects.read todo_path in
	if line < 1 || line > List.length todos then Error (WrongLine line) else
  let updated = todos |> List.filteri (fun idx _ -> idx <> line - 1) in
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
			read = (fun _ -> read) ;
			write = (fun _ _ -> write)
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
			read = (fun _ -> read) ;
			write = (fun _ _ -> write)
		} = expected)
	)

(* Complete *)
let complete line todo_path done_path effects =
	let* todos = effects.read todo_path in
	if line < 1 || line > List.length todos then Error (WrongLine line) else
	let updated = todos |> List.filteri (fun idx _ -> idx <> line - 1) in
	let todo = List.nth todos (line - 1) in
	let* done_todos = effects.read done_path in
	let* _ = effects.write (todo :: done_todos) done_path in
	let* _ = effects.write updated todo_path in
	Ok updated

let () =
	[
		(Error FileSystem, 1, Ok() 						, Error FileSystem	 );
		(Ok["todo"]      , 2, Ok()				    , Error (WrongLine 2));
		(Ok["todo"]			 , 1, Error FileSystem, Error FileSystem	 );
		(Ok["todo"]			 , 1, Ok()						, Ok[]							 )
	] |> List.iter (fun (read, line, write, expected) ->
		assert (complete line "todo path" "done path" {
			read = (fun _ -> read);
			write = (fun _ _ -> write)
		} = expected)
	)

(* Complete writes to done_path before updating todo_path *)
let () =
  let history = ref [] in
  let fx = {
    read  = (fun _ -> Ok ["tarea"]);
    write = (fun _ path -> history := !history @ [path]; Ok ())
  } in
  let _ = complete 1 "todo path" "done path" fx in
  assert (!history = ["done path"; "todo path"])
