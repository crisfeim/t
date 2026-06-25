type error = FileSystem
type todo = string
type path = string

type effects = {
	read : path -> (string list, error) result;
	write: todo list -> path -> (unit, error) result;
}

let ( let* ) = Result.bind

let run_list todo_path fx =
	let* todos = fx.read todo_path in
	let formatted = todos |> List.mapi (fun idx content -> string_of_int (idx + 1) ^ " " ^ content) in
	Ok formatted

let run_add todo todo_path fx =
	let* todos = fx.read todo_path in
	let updated = todos @ [todo] in
	let* _ = fx.write updated todo_path in
	Ok()

(* Run list test case *)
let () =
	[
	  (Error FileSystem			 , Error FileSystem					);
	  (Ok ["compra"; "lavar"], Ok ["1 compra"; "2 lavar"])
	]
	|> List.iter (fun (read, expected) ->
			assert (run_list "any todo path" {
     		read  = (fun _ -> read);
       	write = (fun _ _ -> Ok ());
   			} = expected
			)
  )

(* Run add *)
let () =
	[
		(* read *)       (* write *)       (* expected *)
		(Error FileSystem, Ok()            , Error FileSystem);
		(Ok[]            , Error FileSystem, Error FileSystem);
		(Ok[]						 , Ok()					   , Ok()            )
	] |> List.iter (fun (read, write, expected) ->
		assert (run_add "any todo path" "any done path" {
			read = (fun _ -> read) ;
			write = (fun _ _ -> write)
		} = expected)
	)
