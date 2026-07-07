open Test_lib
open T

type command =
| List of path
| Add of string
| Complete of int list
| Remove of int list
| Edit of int
| Commit of int * bool

let get_line string from = int_of_string (String.sub string from (String.length string - from))

let cmd operator str =
	String.length str > 1
  && String.get str 0 = operator
  && Option.is_some (int_of_string_opt (String.sub str 1 (String.length str - 1)))

let drop n str =
	if n >=String.length str then ""
	else String.sub str n (String.length str - n)

let is_numeric str = Option.is_some (int_of_string_opt str)

let batch_cmd operator str =
	String.length str > 1
  && String.get str 0 = operator
	&& (drop 1 str
		|> String.split_on_char ','
		|> List.for_all is_numeric)

let cmd_c_editing str =
	String.length str > 2
	&& String.get str 0 = 'c'
	&& String.get str 1 = '~'
	&& Option.is_some (int_of_string_opt (String.sub str 2 (String.length str - 2)))

let list_from string = String.split_on_char ',' string

let parser todo_path args = match args with
	| [] -> Some (List todo_path)
	| [single] when batch_cmd '+' single -> Some (Complete ((list_from (drop 1 single)) |> List.map int_of_string))
	| [single] when batch_cmd '-' single -> Some (Remove ((list_from (drop 1 single)) |> List.map int_of_string))
	| [single] when cmd '~' single -> Some (Edit (int_of_string (drop 1 single)))
	| [single] when cmd 'c' single -> Some (Commit (int_of_string (drop 1 single), false))
	| [single] when cmd_c_editing single -> Some (Commit (int_of_string (drop 2 single), true))
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

	test "Complete one" (fun expect ->
		let command = parser "any path" ["+32"] in
		expect.equal command (Some (Complete [32]))
	);

	test "Complete many" (fun expect ->
		let command = parser "any path" ["+32,24"] in
		expect.equal command (Some (Complete [32;24]))
	);

	test "Remove" (fun expect ->
		let command = parser "any path" ["-32"] in
		expect.equal command (Some (Remove [32]))
	);

	test "Remove many" (fun expect ->
		let command = parser "any path" ["-32,24"] in
		expect.equal command (Some (Remove [32;24]))
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
