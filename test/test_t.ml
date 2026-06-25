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

(* Run remove *)
let remove line todo_path effects =
	let* todos = effects.read todo_path in
	if line < 1 || line > List.length todos then
		Error (WrongLine line)
	else
	Ok()


let () =
	[
		(Error FileSystem, 1 , Ok() , Error FileSystem);
		(Ok ["todo 1"]   , 2 , Ok() , Error (WrongLine 2))
	] |> List.iter (fun (read, line, write, expected) ->
		assert (remove line "todo path" {
			read = (fun _ -> read) ;
			write = (fun _ _ -> write)
		} = expected)
	)
