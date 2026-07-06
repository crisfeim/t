open T
open Test
open Test_helpers

let () = case "List" (fun test ->
  [
  (Error `FileSystem, Error `FileSystem);
  (Ok ["compra"; "lavar"], Ok ["1 lavar"; "2 compra"]);
  ]
  |> List.iteri (fun i (read, expected) ->
	  test (case_id i) (fun expect ->
			assert_list expect expected (list "any todo path" { (mock_effects ()) with read = (fun _ -> read) })
	  )
  )
)

let () = case "Add" (fun test ->
  [
  (Error `FileSystem, Ok (), Error `FileSystem);
  (Ok [], Error `FileSystem, Error `FileSystem);
  (Ok [], Ok (), Ok "any todo");
  ]
  |> List.iteri (fun i (read, write, expected) ->
    test (case_id i) (fun expect ->
    	assert_str expect expected (add "any todo" "any todo path" { (mock_effects ()) with
       read = (fun _ -> read);
       write = (fun _ _ -> write) })
    ))
)

let () = case "Remove" (fun test ->
  [
  (Error `FileSystem, 1, Ok (), Error `FileSystem);
  (Ok ["any todo"], 2, Ok (), Error (`WrongLine 2));
  (Ok ["any todo"], 1, Error `FileSystem, Error `FileSystem);
  (Ok ["any todo"], 1, Ok (), Ok "any todo");
  ]
  |> List.iteri (fun i (read, line, write, expected) ->
    test (case_id i) (fun expect ->
    	assert_str expect expected (remove line "any todo path" { (mock_effects ()) with
       read = (fun _ -> read);
       write = (fun _ _ -> write) })
    )
  )
)

let () = case "Complete" (fun test ->
  [
  (Error `FileSystem, 1, Ok (), Error `FileSystem);
  (Ok ["any todo"], 2, Ok (), Error (`WrongLine 2));
  (Ok ["any todo"], 1, Error `FileSystem, Error `FileSystem);
  (Ok ["any todo"], 1, Ok (), Ok "any todo");
  ]
  |> List.iteri (fun i (read, line, write, expected) ->
    test (case_id i) (fun expect ->
    	assert_str expect expected (complete line "any todo path" "any done path" { (mock_effects ()) with
       read = (fun _ -> read);
       write = (fun _ _ -> write) })
    ));

  test "writes to done_path before updating todo_path" (fun expect ->
    let write_calls = ref [] in
    let _ = complete 1 "any todo path" "any done path" { (mock_effects ()) with
      read = (fun path -> if path = "any done path" then Ok [] else Ok ["tarea"]);
      write = (fun data path -> write_calls := !write_calls @ [(path, data)]; Ok ());
      now = (fun () -> "202606252301");
    } in

    expect.equal !write_calls [
    ("any done path", ["202606252301 tarea"]);
    ("any todo path", [])
    ]
  )
)

let () = case "Edit" (fun test ->
  [
  (Error `FileSystem, 1, Ok "any edition", Ok (), Error `FileSystem);
  (Ok ["any todo"], 2, Ok "any edition", Ok (), Error (`WrongLine 2));
  (Ok ["any todo"], 1, Error `Editor, Ok (), Error `Editor);
  (Ok ["any todo"], 1, Ok "any edition", Error `FileSystem, Error `FileSystem);
  (Ok ["any todo"], 1, Ok "any edition", Ok (), Ok());
  ]
  |> List.iteri (fun i (read, line, editor, write, expected) ->
    test (case_id i) (fun expect ->
    	assert_unit expect expected (edit line "any todo path" { (mock_effects ()) with
       read = (fun _ -> read);
       write = (fun _ _ -> write);
       editor = (fun _ -> editor); })
    ));

  test "writes edited data" (fun expect ->
    let write_calls = ref [] in
    let _ = edit 1 "any todo path" { (mock_effects ()) with
      read = (fun _ -> Ok ["any todo"]);
      write = (fun todos _ -> write_calls := todos :: !write_calls; Ok ());
      editor = (fun _ -> Ok "edited");
    } in
    expect.equal !write_calls [["edited"]]
  );

  test "avoids unnecessary I/O when editor returns empty" (fun expect ->
    let did_write = ref false in
    let _ = edit 1 "any todo path" { (mock_effects ()) with
      read = (fun _ -> Ok ["any todo"]);
      write = (fun _ _ -> did_write := true; Ok ());
      editor = (fun _ -> Ok "");
    } in
    expect.is (not !did_write) "expected no write"
  );

  test "avoids unnecessary I/O when editor returns unchanged" (fun expect ->
    let did_write = ref false in
    let _ = edit 1 "any todo path" { (mock_effects ()) with
      read = (fun _ -> Ok ["any todo"]);
      write = (fun _ _ -> did_write := true; Ok ());
      editor = (fun _ -> Ok "any todo");
    } in
    expect.is (not !did_write) "expected no write"
  )
)

let () = case "Commit" (fun test ->
  [
  (None    , Ok ["any todo"]  , 1, Ok "any edition", Ok (), Ok (), Error `NoRepository);
  (any_repo, Error `FileSystem, 1, Ok "any edition", Ok (), Ok (), Error `FileSystem);
  (any_repo, Ok ["any todo"], 2, Ok "any edition", Ok (), Ok (), Error (`WrongLine 2));
  (any_repo, Ok ["any todo"], 1, Error `Editor, Ok (), Ok (), Error `Editor);
  (any_repo, Ok ["any todo"], 1, Ok "", Ok (), Ok (), Error (`CommitError "Commit aborted due to empty message"));
  (any_repo, Ok ["any todo"], 1, Ok "any edition", Error (`CommitError "any error"), Ok (), Error (`CommitError "any error"));
  (any_repo, Ok ["any todo"], 1, Ok "any edition", Ok (), Error `FileSystem, Error `FileSystem);
  (any_repo, Ok ["any todo"], 1, Ok "any edition", Ok (), Ok (), Ok());
  ]
  |> List.iteri (fun i (repo, read, line, editor, commit_r, write, expected) ->
    test (case_id i) (fun expect ->
      assert_unit expect expected
        (commit line "any todo path" "any done path" true { (mock_effects ()) with
          read = (fun _ -> read);
          write = (fun _ _ -> write);
          editor = (fun _ -> editor);
          commit = (fun _ _ -> commit_r);
          get_repo = (fun _ -> repo); })
    ));

  test "archives todo in correct order on success" (fun expect ->
    let write_calls = ref [] in
    let _ = commit 1 "any todo path" "any done path" true { (mock_effects ()) with
      read = (fun path -> if path = "any done path" then Ok ["20260625 some"] else Ok ["any todo"]);
      write = (fun data path -> write_calls := !write_calls @ [(path, data)]; Ok ());
      now = (fun () -> "20260627");
      editor = (fun _ -> Ok "edited");
      get_repo = (fun _ -> any_repo);
    } in
    expect.equal
      [("any done path", ["20260627 edited"; "20260625 some"]); ("any todo path", [])]
      !write_calls
  );

  test "uses editor output as commit message" (fun expect ->
    let commit_msg = ref "" in
    let _ = commit 1 "any todo path" "any done path" true { (mock_effects ()) with
      read = (fun path -> if path = "any done path" then Ok [] else Ok ["any todo"]);
      editor = (fun _ -> Ok "edited");
      commit = (fun msg _ -> commit_msg := msg; Ok ());
      get_repo = (fun _ -> any_repo);
    } in
    expect.equal "edited" !commit_msg
  );

  test "uses todo as commit message when open_editor is false" (fun expect ->
      let commit_msg = ref "" in
      let _ = commit 1 "any todo path" "any done path" false { (mock_effects ()) with
        read = (fun path -> if path = "any done path" then Ok [] else Ok ["any todo"]);
        commit = (fun msg _ -> commit_msg := msg; Ok ());
        get_repo = (fun _ -> any_repo);
      } in
      expect.equal "any todo" !commit_msg
  )
)

let () = case "Projects" (fun test ->
  [
  (Error `FileSystem, Error `FileSystem);
  (Ok ["p1"; "p2"], Ok ["p1"; "p2"]);
  ]
  |> List.iteri (fun i (projects_r, expected) ->
    test (case_id i) (fun expect ->
      assert_list expect expected (projects { (mock_effects ()) with projects = (fun () -> projects_r) }))
  )
)

let sort_matches projects =
	List.sort (fun path1 path2 ->
		let count1 = List.length (String.split_on_char '/' path1) in
    let count2 = List.length (String.split_on_char '/' path2) in

    if count1 <> count2 then
      compare count1 count2
    else
    	let len1 = String.length path1 in
     	let len2 = String.length path2 in

      if len1 <> len2 then
     		compare len1 len2
      else
     		String.compare path1  path2
	) projects

let project name effects =
  let* projects = projects effects in

  match projects |> sort_matches |> List.find_opt (fun path -> List.mem name (String.split_on_char '/' path)) with
  | Some found_path -> list found_path effects
  | None -> Error `FileSystem


let () = case "Project" (fun test ->
	[
	(Error `FileSystem, Ok [], Error `FileSystem);
	(Ok ["/User/any-project"], Error `FileSystem, Error `FileSystem);
	(Ok ["/User/any-project"], Ok ["any todo"], Ok ["1 any todo"])
	]
	|> List.iteri (fun i (project_r, read_r, expected) ->
		test (case_id i) (fun expect ->
			assert_list expect expected (project "any-project" { (mock_effects()) with
				projects = (fun _ -> project_r);
				read = (fun _ -> read_r)
			 })
		)
	);
)

let () = case "Sort matches" (fun test ->
	test "sort_matches: prioritizes shallowest path" (fun expect ->
	  let input = ["/User/nested/any-project"; "/User/any-project"] in
	  expect.equal ["/User/any-project"; "/User/nested/any-project"] (sort_matches input)
	);

	test "sort_matches: prioritizes shortest path on equal depth" (fun expect ->
	  let input = ["/User/nested_longest/any-project"; "/User/short/any-project"] in
	  expect.equal ["/User/short/any-project"; "/User/nested_longest/any-project"] (sort_matches input)
	);

	test "sort_matches: falls back to alphabetical order on equal depth and length" (fun expect ->
	  let input = ["/User/t/any-project"; "/User/a/any-project"] in
	  expect.equal ["/User/a/any-project"; "/User/t/any-project"] (sort_matches input)
	)
)
