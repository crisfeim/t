open Test_lib
open T

type command =
| List of path
| Add of string
| Complete of int

let get_substring string from = String.sub string from (String.length string - from)

let parse_compact cmd =
  if String.length cmd > 1 && String.get cmd 0 = '+' then
    let num_str = get_substring cmd 1 in
    match int_of_string_opt num_str with
    | Some line -> Some (Complete line)
    | None -> None
  else
    None

let parser todo_path args = match args with
	| [] -> Some (List todo_path)
	| [single_arg] -> parse_compact single_arg
	| values -> Some (Add (String.concat " " values))

let () = case "Parser" (fun test ->
	test "List" (fun expect ->
		let command = parser  "any path" [] in
		expect.equal command (Some (List "any path"))
	);

	test "Add" (fun expect ->
		let command = parser "any path" ["new";"todo"] in
		expect.equal command (Some (Add "new todo"))
	);

	test "Complete" (fun expect ->
		let command = parser "any path" ["+32"] in
		expect.equal command (Some (Complete 32))
	)
)
