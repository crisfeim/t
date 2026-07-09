open Test_lib
open Test_helpers
open T

let any_todo_path = "any-todo-path"

let () = case "Parser" (fun test ->
	test "Echo" (fun expect ->
		expect.equal (fmt_option fmt_command) (parser any_todo_path ["10"]) (Some (Echo (any_todo_path, 10)))
	);

	test "List" (fun expect ->
		expect.equal (fmt_option fmt_command) (parser any_todo_path []) (Some (List any_todo_path))
	);

	test "List projects" (fun expect ->
		expect.equal (fmt_option fmt_command) (parser any_todo_path ["."]) (Some ListProjects)
	);

	test "List doing across projects" (fun expect ->
		expect.equal (fmt_option fmt_command) (parser any_todo_path [".@"]) (Some ListDoingAcrossProjects)
	);

	test "List range" (fun expect ->
		expect.equal (fmt_option fmt_command) (parser any_todo_path ["1...5"]) (Some (ListRange (any_todo_path, [1;2;3;4;5])))
	);

	test "Parse range" (fun expect ->
		expect.equal fmt_int_list (parse_range "1...3") [1;2;3]
	);

	test "List doing" (fun expect ->
		expect.equal (fmt_option fmt_command) (parser any_todo_path ["@"]) (Some (ListDoing any_todo_path))
	);

	test "Add" (fun expect ->
		expect.equal (fmt_option fmt_command) (parser any_todo_path ["new";"todo"]) (Some (Add (any_todo_path, "new todo")))
	);

	test "Complete one" (fun expect ->
		expect.equal (fmt_option fmt_command) (parser any_todo_path ["+32"]) (Some (Complete (any_todo_path, [32])))
	);

	test "Complete many" (fun expect ->
		expect.equal (fmt_option fmt_command) (parser any_todo_path ["+32,24"]) (Some (Complete (any_todo_path, [32;24])))
	);

	test "Remove" (fun expect ->
		expect.equal (fmt_option fmt_command) (parser any_todo_path ["-32"]) (Some (Remove (any_todo_path, [32])))
	);

	test "Remove many" (fun expect ->
		expect.equal (fmt_option fmt_command) (parser any_todo_path ["-32,24"]) (Some (Remove (any_todo_path, [32;24])))
	);

	test "Edit" (fun expect ->
		expect.equal (fmt_option fmt_command) (parser any_todo_path [":32"]) (Some (Edit (any_todo_path, 32)))
	);

	test "Edit .todo" (fun expect ->
		expect.equal (fmt_option fmt_command) (parser any_todo_path [":"]) (Some (EditFile any_todo_path))
	);

	test "Commit" (fun expect ->
		expect.equal (fmt_option fmt_command) (parser  any_todo_path ["c32"]) (Some (Commit (any_todo_path, 32, false)))
	);

	test "Commit editing" (fun expect ->
		expect.equal (fmt_option fmt_command) (parser any_todo_path ["c:32"]) (Some (Commit (any_todo_path, 32, true)))
	);

	test "Mark as doing" (fun expect ->
		expect.equal (fmt_option fmt_command) (parser any_todo_path ["@32"]) (Some (Doing (any_todo_path, 32)))
	);
)

let () = case "Project namespacing" (fun test ->
  let effects = { (Test_helpers.mock_effects()) with projects = (fun () -> Ok["/User/some-project/.todo"]) } in
  let cases = [
    ("List",     [], Some (List "/User/some-project/.todo"));
    ("Complete", ["+1,2"], Some (Complete ("/User/some-project/.todo", [1;2])));
    ("Remove",   ["-5,2"], Some (Remove ("/User/some-project/.todo", [5; 2])));
    ("Edit",     [":10"], Some (Edit ("/User/some-project/.todo", 10)));
    ("Doing",    ["@1"], Some (Doing ("/User/some-project/.todo", 1)));
    ("Commit",   ["c1"], Some (Commit ("/User/some-project/.todo", 1, false)));
    ("Add",      ["New"; "Todo"], Some(Add ("/User/some-project/.todo", "New Todo")))
  ] in
  cases
  |> List.iter (fun (desc, args, expected) ->
    test desc (fun expect ->
      expect.equal (fmt_option fmt_command) expected (command_router any_todo_path ([".some-project"] @ args) effects)
    )
  )
)
