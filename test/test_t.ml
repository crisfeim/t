type error = FileSystem

type effects = {
	read: string -> (string list, error) result;
}

let run_list todo_path fx = fx.read todo_path

(* run list returns error on read error *)
let () =
	let fx = { read = fun path -> Error FileSystem } in
	match run_list "any path" fx with
	| Error FileSystem -> ()
	| _ -> assert false
