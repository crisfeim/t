type error = FileSystem

type effects = {
	read: string -> (string list, error) result;
}

let ( let* ) = Result.bind

let run_list todo_path fx =
	let* lines = fx.read todo_path in
	Ok lines

(* run list returns error on read error *)
let () =
	let fx = { read = fun path -> Error FileSystem } in
	match run_list "any path" fx with
	| Error FileSystem -> ()
	| _ -> assert false

(* run list returns list on successful read *)
let () =
	let fx = { read = fun path -> Ok ["todo 1"] } in
	match run_list "any path" fx with
	| Error FileSystem -> assert false
	| Ok list -> assert (list == ["todo 1"])
