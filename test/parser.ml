open Test_lib
open T

type command =
| List of path
| Add of string
| Complete of int
| Remove of int
| Edit of int

let get_line string = int_of_string (String.sub string 1 (String.length string - 1))

let is_complete_cmd str =
  String.length str > 1
  && String.get str 0 = '+'
  && Option.is_some (int_of_string_opt (String.sub str 1 (String.length str - 1)))

let is_remove_cmd str =
  String.length str > 1
  && String.get str 0 = '-'
  && Option.is_some (int_of_string_opt (String.sub str 1 (String.length str - 1)))

let is_edit_cmd str =
  String.length str > 1
  && String.get str 0 = '~'
  && Option.is_some (int_of_string_opt (String.sub str 1 (String.length str - 1)))

let parser todo_path args = match args with
	| [] -> Some (List todo_path)
	| [single] when is_complete_cmd single -> Some (Complete (get_line single))
	| [single] when is_remove_cmd single -> Some (Remove (get_line single))
	| [single] when is_edit_cmd single -> Some (Edit (get_line single))
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
	);

	test "Remove" (fun expect ->
		let command = parser "any path" ["-32"] in
		expect.equal command (Some (Remove 32))
	);

	test "Edit" (fun expect ->
		let command = parser "any path" ["~32"] in
		expect.equal command (Some (Edit 32))
	);
)
