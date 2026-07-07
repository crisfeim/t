open Test_lib

type command =
| Add of string

let parser args = Add args

let () = case "Parser" (fun test ->
	test "Add" (fun expect ->
		let command = parser "new todo" in
		expect.equal command (Add "new todo")
	)
)
