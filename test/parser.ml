open Test_lib
open Test_helpers
open T.Parser

let any_todo_path = "any-todo-path"

let () = case "Parser" (fun test ->

	test "count" (fun expect ->
		expect.equal (fmt_command) (Count) (parser any_todo_path ["count"])
	);

	test "Echo" (fun expect ->
		expect.equal (fmt_command) (parser any_todo_path ["10"]) (Echo (any_todo_path, 10))
	);

	test "List" (fun expect ->
		expect.equal (fmt_command) (parser any_todo_path []) (List any_todo_path)
	);

	test "List projects" (fun expect ->
		expect.equal (fmt_command) (parser any_todo_path ["."]) ListProjects
	);

	test "List doing across projects" (fun expect ->
		expect.equal (fmt_command) (parser any_todo_path [".@"]) ListDoingAcrossProjects
	);

	test "List range" (fun expect ->
		expect.equal (fmt_command) (parser any_todo_path ["1...5"]) (ListRange (any_todo_path, [1;2;3;4;5]))
	);

	test "Parse range" (fun expect ->
		expect.equal fmt_int_list (parse_range "1...3") [1;2;3]
	);

	test "List doing" (fun expect ->
		expect.equal (fmt_command) (parser any_todo_path ["@"]) (ListDoing any_todo_path)
	);

	test "Add" (fun expect ->
		expect.equal (fmt_command) (parser any_todo_path ["new";"todo"]) (Add (any_todo_path, "new todo"))
	);

	test "Complete one" (fun expect ->
		expect.equal (fmt_command) (parser any_todo_path ["+32"]) (Complete (any_todo_path, [32]))
	);

	test "Complete many" (fun expect ->
		expect.equal (fmt_command) (parser any_todo_path ["+32,24"]) (Complete (any_todo_path, [32;24]))
	);

	test "Remove" (fun expect ->
		expect.equal (fmt_command) (parser any_todo_path ["-32"]) (Remove (any_todo_path, [32]))
	);

	test "Remove many" (fun expect ->
		expect.equal (fmt_command) (parser any_todo_path ["-32,24"]) (Remove (any_todo_path, [32;24]))
	);

	test "Edit" (fun expect ->
		expect.equal (fmt_command) (parser any_todo_path [":32"]) (Edit (any_todo_path, 32))
	);

	test "Update" (fun expect ->
		expect.equal (fmt_command) (parser any_todo_path [":32"; "value"]) (Update (any_todo_path, 32, "value"))
	);

	test "Edit .todo" (fun expect ->
		expect.equal (fmt_command) (parser any_todo_path [":"]) (EditFile any_todo_path)
	);

	test "Commit" (fun expect ->
		expect.equal (fmt_command) (parser  any_todo_path ["c32"]) (Commit (any_todo_path, 32, false))
	);

	test "Commit editing" (fun expect ->
		expect.equal (fmt_command) (parser any_todo_path ["c:32"]) (Commit (any_todo_path, 32, true))
	);

	test "Mark as doing" (fun expect ->
		expect.equal (fmt_command) (parser any_todo_path ["@32"]) (Doing (any_todo_path, 32))
	);
)

let () = case "Project namespacing" (fun test ->
  let effects = { (Test_helpers.mock_effects()) with projects = (fun () -> Ok["/User/some-project/.todo"]) } in
  let cases = [
    ("List",     [], List "/User/some-project/.todo");
    ("Complete", ["+1,2"], Complete ("/User/some-project/.todo", [1;2]));
    ("Remove",   ["-5,2"], Remove ("/User/some-project/.todo", [5; 2]));
    ("Edit",     [":10"], Edit ("/User/some-project/.todo", 10));
    ("Doing",    ["@1"], Doing ("/User/some-project/.todo", 1));
    ("Commit",   ["c1"], Commit ("/User/some-project/.todo", 1, false));
    ("Add",      ["New"; "Todo"], Add ("/User/some-project/.todo", "New Todo"))
  ] in
  cases
  |> List.iter (fun (desc, args, expected) ->
    test desc (fun expect ->
      expect.equal (fmt_option fmt_command) (Some expected) (command_router any_todo_path ([".some-project"] @ args) effects)
    )
  )
)
