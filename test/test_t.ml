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

(* run list fails on read error *)
let () =
	let fx = { read = (fun _ -> Error FileSystem) ; write = (fun _ _ -> Ok()) } in
	match run_list "any path" fx with
	| Error FileSystem -> ()
	| _ -> assert false

(* run list succeeds on successful read *)
let () =
	let fx = { read = (fun _ -> Ok ["todo 1"]) ; write = (fun _ _ -> Ok()) } in
	match run_list "any path" fx with
	| Error FileSystem -> assert false
	| Ok list -> assert (list = ["1 todo 1"])


let run_add todo todo_path fx =
	let* todos = fx.read todo_path in
	let updated = todos @ [todo] in
	let* _ = fx.write updated todo_path in
	Ok()

(* run add fails on writing failure *)
let () =
	let fx = { read = (fun _ -> Ok []) ; write = (fun _ _ -> Error FileSystem) } in
	match run_add "any todo" "any path" fx with
	| Error FileSystem -> ()
	| _ -> assert false
