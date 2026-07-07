open Test_lib
open T

type command =
| List of path
| Add of string
| Complete of int
| Remove of int
| Edit of int
| Commit of int * bool

let get_line string from = int_of_string (String.sub string from (String.length string - from))

let cmd operator str =
	String.length str > 1
  && String.get str 0 = operator
  && Option.is_some (int_of_string_opt (String.sub str 1 (String.length str - 1)))

let commit_editing str =
	String.length str > 2
	&& String.get str 0 = 'c'
	&& String.get str 1 = '~'
	&& Option.is_some (int_of_string_opt (String.sub str 2 (String.length str - 2)))

let parser todo_path args = match args with
	| [] -> Some (List todo_path)
	| [single] when cmd '+' single -> Some (Complete (get_line single 1))
	| [single] when cmd '-' single -> Some (Remove (get_line single 1))
	| [single] when cmd '~' single -> Some (Edit (get_line single 1))
	| [single] when cmd 'c' single -> Some (Commit ((get_line single 1), false))
	| [single] when commit_editing single -> Some (Commit ((get_line single 2), true))
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

	test "Commit" (fun expect ->
		let command = parser "any path" ["c32"] in
		expect.equal command (Some (Commit (32, false)))
	);

	test "Commit editing" (fun expect ->
		let command = parser "any path" ["c~32"] in
		expect.equal command (Some (Commit (32, true)))
	);
)
