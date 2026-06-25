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

(* Run list fails on read error *)
let () =
	let fx = { read = (fun _ -> Error FileSystem) ; write = (fun _ _ -> Ok()) } in
	match run_list "any path" fx with
	| Error FileSystem -> ()
	| _ -> assert false

(* Run list succeeds on successful read *)
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

(* Run add fails on read failure *)
let () =
		let fx = { read = (fun _ -> Error FileSystem) ; write = (fun _ _ -> Ok() ) } in
		match run_add "any todo" "any path" fx with
		| Error FileSystem -> ()
		| _ -> assert false

(* Run add fails on writing failure *)
let () =
	let fx = { read = (fun _ -> Ok []) ; write = (fun _ _ -> Error FileSystem) } in
	match run_add "any todo" "any path" fx with
	| Error FileSystem -> ()
	| _ -> assert false


let run_list_matrix = [
  (* Caso 1: Error en la lectura -> Debe propagar el error *)
  (Error FileSystem, Error FileSystem);
  (* Caso 2: Lectura exitosa vacía -> Lista vacía *)
  (Ok [], Ok []);
  (* Caso 3: Lectura exitosa con datos -> Lista formateada *)
  (Ok ["compra"; "lavar"], Ok ["1 compra"; "2 lavar"])
]

(* 3. El Ejecutor de la Matriz *)
let () =
  run_list_matrix |> List.iter (fun (effect_behaviour, expected_result) ->
    (* Configurar el SUT (System Under Test) dinámicamente basado en la fila *)
    let fx = {
      read =  (fun _ -> effect_behaviour);
      write = (fun _ _ -> Ok ());
    } in

    (* Ejecutar y asegurar la coincidencia absoluta *)
    let actual_result = run_list "any_path" fx in
    assert (actual_result = expected_result)
  )
