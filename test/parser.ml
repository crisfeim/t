open Test_lib
open T

type command =
| List of path
| Add of string

let parser todo_path args = match args with
	| [] -> List todo_path
	| values -> Add (String.concat " " values)

let () = case "Parser" (fun test ->
	test "List" (fun expect ->
		let command = parser  "any path" [] in
		expect.equal command (List "any path")
	);

	test "Add" (fun expect ->
		let command = parser "any path" ["new";"todo"] in
		expect.equal command (Add "new todo")
	)
)
