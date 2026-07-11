open T.Logic
open Test_lib
open Test_helpers

let () = case "List" (fun test ->
  [
  (Error `FileSystem, Error `FileSystem);
  (Ok ["compra"; "lavar"], Ok ["1 compra"; "2 lavar"]);
  ]
  |>
  List.iteri (fun i (read, expected) ->
  	test (case_id i) (fun expect ->
  		expect.equal fmt_result_list expected (list "any todo path" { (mock_effects ()) with read = (fun _ -> read) })
	  )
	)
)

let () = case "List doing" (fun test ->
  [
  (Error `FileSystem, Error `FileSystem);
  (Ok ["compra @doing"; "lavar"; "another @doing"], Ok ["1 compra @doing"; "3 another @doing"]);
  ]
  |>
  List.iteri (fun i (read, expected) ->
  	test (case_id i) (fun expect ->
  		expect.equal fmt_result_list expected (list_doing "any todo path" { (mock_effects ()) with read = (fun _ -> read) })
	  )
	)
)
let () = case "List doing across projects" (fun test ->
   [
    (Error `FileSystem, (fun _ -> Error `FileSystem), Error `FileSystem);
    (Ok [], (fun _ -> Ok []), Ok []);
    (Ok ["proj1"; "proj2"; "proj3"],
     (fun path -> match path with
       | "proj1" -> Ok ["compra @doing"; "lavar"]
       | "proj2" -> Ok ["nada aqui"]
       | "proj3" -> Ok ["otra @doing"; "mas @doing"]
       | _ -> Ok []),
     Ok [
       ("proj1", ["1 compra @doing"]);
       ("proj3", ["1 otra @doing"; "2 mas @doing"]);
     ]);
  ]
  |>
  List.iteri (fun i (projects_result, read_fn, expected) ->
  	test "fail" (fun expect ->
 		expect.equal fmt_result_projects_doing expected (list_doing_across_projects  { (mock_effects ()) with
      projects = (fun _ -> projects_result);
      read = read_fn });
   )
  )
)


let () = case "Add" (fun test ->
  [
  (Error `FileSystem, Ok (), Error `FileSystem);
  (Ok [], Error `FileSystem, Error `FileSystem);
  (Ok [], Ok (), Ok "any todo");
  ]|>
  List.iteri (fun i (read, write, expected) ->
    test (case_id i) (fun expect ->
	   	expect.equal fmt_result_string expected (add "any todo" "any todo path" { (mock_effects ()) with
	       read = (fun _ -> read);
	       write = (fun _ _ -> write) })
    )
 	);
)

let () = case "Remove" (fun test ->
  [
  (Error `FileSystem, 1, Ok (), Error `FileSystem);
  (Ok ["any todo"], 2, Ok (), Error (`WrongLine 2));
  (Ok ["any todo"], 1, Error `FileSystem, Error `FileSystem);
  (Ok ["any todo"], 1, Ok (), Ok "any todo");
  ]|>
  List.iteri (fun i (read, line, write, expected) ->
		test (case_id i) (fun expect ->
		 	expect.equal fmt_result_string expected (remove line "any todo path" { (mock_effects ()) with
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
  (Ok ["any todo @doing"], 1, Ok (), Ok "any todo");
  ] |>
  List.iteri (fun i (read, line, write, expected) ->
    test (case_id i) (fun expect ->
    	expect.equal fmt_result_string expected (complete line "any todo path" "any done path" { (mock_effects ()) with
       read = (fun _ -> read);
       write = (fun _ _ -> write) })
    )
 	);

  test "writes to done_path before updating todo_path" (fun expect ->
    let write_calls = ref [] in
    let _ = complete 1 "any todo path" "any done path" { (mock_effects ()) with
      read = (fun path -> if path = "any done path" then Ok [] else Ok ["tarea"]);
      write = (fun data path -> write_calls := !write_calls @ [(path, data)]; Ok ());
      now = (fun () -> "202606252301");
    } in

    expect.equal fmt_tuple !write_calls [
    ("any done path", ["202606252301 tarea"]);
    ("any todo path", [])
    ]
  )
)

let () = case "Update" (fun test ->
	[
	Error `FileSystem, 1, Error `FileSystem, "any update", Error `FileSystem ;
	Ok["any todo"], 1, Error `FileSystem, "any update", Error `FileSystem;
	Ok["any todo"], 2, Ok(), "any update", Error (`WrongLine 2);
	Ok["any todo"], 1, Ok(), "any update", Ok "any update"
	]
	|>
	List.iteri (fun i (read, line, write, new_content, expected) ->
		test (case_id i) (fun expect ->
			expect.equal fmt_result_string expected (update "any-path" line new_content { (mock_effects()) with
				read = (fun _ -> read);
				write = (fun _ _ -> write)
			})
		)
	)
)

let () = case "Edit" (fun test ->
  [
  (Error `FileSystem, 1, Ok "any edition", Ok (), Error `FileSystem);
  (Ok ["any todo"], 2, Ok "any edition", Ok (), Error (`WrongLine 2));
  (Ok ["any todo"], 1, Error `Editor, Ok (), Error `Editor);
  (Ok ["any todo"], 1, Ok "any edition", Error `FileSystem, Error `FileSystem);
  (Ok ["any todo"], 1, Ok "some edition", Ok (), Ok "some edition");
  ] |>
  List.iteri (fun i (read, line, editor, write, expected) ->
    test (case_id i) (fun expect ->
   		expect.equal fmt_result_unit expected (edit line "any todo path" { (mock_effects ()) with
      	read = (fun _ -> read);
       	write = (fun _ _ -> write);
        editor = (fun _ -> editor); })
    )
  );

  test "writes edited data" (fun expect ->
    let write_calls = ref [] in
    let _ = edit 1 "any todo path" { (mock_effects ()) with
      read = (fun _ -> Ok ["any todo"]);
      write = (fun todos _ -> write_calls := todos :: !write_calls; Ok ());
      editor = (fun _ -> Ok "edited");
    } in
    expect.equal fmt_string_list_of_list !write_calls [["edited"]]
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

let () = case "EditFile" (fun test ->
  [
  (Error `FileSystem, Ok "any edition", Ok (), Error `FileSystem);
  (Ok ["A"; "B"], Error `Editor, Ok (), Error `Editor);
  (Ok ["A"; "B"], Ok "A\nB\nC", Error `FileSystem, Error `FileSystem);
  (Ok ["A"; "B"], Ok "A\nB\nC", Ok (), Ok "A\nB\nC");
  ] |>
  List.iteri (fun i (read, editor, write, expected) ->
    test (case_id i) (fun expect ->
    	expect.equal fmt_result_unit expected (edit_file "any todo path" { (mock_effects ()) with
      	read = (fun _ -> read);
       	write = (fun _ _ -> write);
        editor = (fun _ -> editor); })
    )
  );

  test "writes each edited line split by newline" (fun expect ->
    let write_calls = ref [] in
    let _ = edit_file "any todo path" { (mock_effects ()) with
      read = (fun _ -> Ok ["A"; "B"]);
      write = (fun todos _ -> write_calls := todos :: !write_calls; Ok ());
      editor = (fun _ -> Ok "A\nB\nC");
    } in
    expect.equal fmt_string_list_of_list !write_calls [["A"; "B"; "C"]]
  );


  test "avoids write when editor returns unchanged" (fun expect ->
    let did_write = ref false in
    let _ = edit_file "any todo path" { (mock_effects ()) with
      read = (fun _ -> Ok ["A"; "B"]);
      write = (fun _ _ -> did_write := true; Ok ());
      editor = (fun _ -> Ok "A\nB");
    } in
    expect.is (not !did_write) "expected no write"
  )
)


let () = case "Commit" (fun test ->
 [
  (None    , Ok ["any todo"]  , 1,  Ok (), Ok (), Error `NoRepository);
  (any_repo, Error `FileSystem, 1,  Ok (), Ok (), Error `FileSystem);
  (any_repo, Ok ["any todo"], 2,  Ok (), Ok (), Error (`WrongLine 2));
  (any_repo, Ok ["any todo"], 1,  Error (`CommitError "any error"), Ok (), Error (`CommitError "any error"));
  (any_repo, Ok ["any todo"], 1,  Ok (), Error `FileSystem, Error `FileSystem);
  (any_repo, Ok ["any todo @doing"], 1,  Ok (), Ok (), Ok "any todo");
  ] |>
  List.iteri (fun i (repo, read, line, commit_r, write, expected) ->
    test (case_id i) (fun expect ->
      expect.equal fmt_result_string expected
        (commit line "any todo path" "any done path" false { (mock_effects ()) with
          read = (fun _ -> read);
          write = (fun _ _ -> write);
          commit = (fun _ _ -> commit_r);
          get_repo = (fun _ -> repo); })
    )
  );

 test "archives todo in correct order on success" (fun expect ->
    let write_calls = ref [] in
    let _ = commit 1 "any todo path" "any done path" true { (mock_effects ()) with
      read = (fun path -> if path = "any done path" then Ok ["20260625 some"] else Ok ["any todo"]);
      write = (fun data path -> write_calls := !write_calls @ [(path, data)]; Ok ());
      now = (fun () -> "20260627");
      editor = (fun _ -> Ok "edited");
      get_repo = (fun _ -> any_repo);
    } in
    expect.equal fmt_tuple
    	[("any done path", ["20260627 edited"; "20260625 some"]); ("any todo path", [])]
      !write_calls
  );
)

let () = case "Commit editing" (fun test ->
  [
  (None    , Ok ["any todo"]  , 1, Ok "any edition", Ok (), Ok (), Error `NoRepository);
  (any_repo, Error `FileSystem, 1, Ok "any edition", Ok (), Ok (), Error `FileSystem);
  (any_repo, Ok ["any todo"], 2, Ok "any edition", Ok (), Ok (), Error (`WrongLine 2));
  (any_repo, Ok ["any todo"], 1, Error `Editor, Ok (), Ok (), Error `Editor);
  (any_repo, Ok ["any todo"], 1, Ok "", Ok (), Ok (), Error (`CommitError "Commit aborted due to empty message"));
  (any_repo, Ok ["any todo"], 1, Ok "any edition", Error (`CommitError "any error"), Ok (), Error (`CommitError "any error"));
  (any_repo, Ok ["any todo"], 1, Ok "any edition", Ok (), Error `FileSystem, Error `FileSystem);
  (any_repo, Ok ["any todo"], 1, Ok "any edition", Ok (), Ok (), Ok "any edition");
  ] |>
  List.iteri (fun i (repo, read, line, editor, commit_r, write, expected) ->
    test (case_id i) (fun expect ->
      expect.equal fmt_result_string expected
        (commit line "any todo path" "any done path" true { (mock_effects ()) with
          read = (fun _ -> read);
          write = (fun _ _ -> write);
          editor = (fun _ -> editor);
          commit = (fun _ _ -> commit_r);
          get_repo = (fun _ -> repo); })
    )
  );

  test "uses editor output as commit message" (fun expect ->
    let commit_msg = ref "" in
    let _ = commit 1 "any todo path" "any done path" true { (mock_effects ()) with
      read = (fun path -> if path = "any done path" then Ok [] else Ok ["any todo"]);
      editor = (fun _ -> Ok "edited");
      commit = (fun msg _ -> commit_msg := msg; Ok ());
      get_repo = (fun _ -> any_repo);
    } in
    expect.equal fmt_string "edited" !commit_msg
  );

  test "uses todo as commit message when open_editor is false" (fun expect ->
      let commit_msg = ref "" in
      let _ = commit 1 "any todo path" "any done path" false { (mock_effects ()) with
        read = (fun path -> if path = "any done path" then Ok [] else Ok ["any todo"]);
        commit = (fun msg _ -> commit_msg := msg; Ok ());
        get_repo = (fun _ -> any_repo);
      } in
      expect.equal fmt_string "any todo" !commit_msg
  )
)

let () = case "Projects" (fun test ->
  [
  (Error `FileSystem, Error `FileSystem);
  (Ok ["p1"; "p2"], Ok ["p1"; "p2"]);
  ] |>
  List.iteri (fun i (projects_r, expected) ->
    test (case_id i) (fun expect ->
    	expect.equal fmt_result_list expected (projects { (mock_effects ()) with projects = (fun () -> projects_r) })
    )
  )
)

let () = case "Set doing" (fun test ->
  [
  (Error `FileSystem, 1, Ok(), Error `FileSystem);
  (Ok["any todo"], 1, Error `FileSystem, Error `FileSystem);
  (Ok["any todo"], 2, Ok(), Error (`WrongLine 2));
  (Ok["some todo"], 1, Ok(), Ok "some todo @doing");
  (Ok["some todo @doing"], 1, Ok(), Ok "some todo");
  ] |>
  List.iteri (fun i (read, line, write, expected) ->
    test (case_id i) (fun expect ->
    	expect.equal fmt_result_string expected (toggle_doing line "any-path" { (mock_effects ()) with
     read = (fun _ -> read);
     write = (fun _ _ -> write )})
    )
  )
)

let () = case "Project" (fun test ->
	[
	(Error `FileSystem, Ok [], Error `FileSystem);
	(Ok ["/User/any-project"], Error `FileSystem, Error `FileSystem);
	(Ok ["/User/any-project"], Ok ["any todo"], Ok ["1 any todo"])
	] |>
	List.iteri (fun i (project_r, read_r, expected) ->
		test (case_id i) (fun expect ->
			expect.equal fmt_result_list expected (project "any-project" { (mock_effects()) with
				projects = (fun _ -> project_r);
				read = (fun _ -> read_r)})
		)
	);
)

let () = case "Sort matches" (fun test ->
	test "sort_matches: prioritizes shallowest path" (fun expect ->
	  let input = ["/User/nested/any-project"; "/User/any-project"] in
	  expect.equal fmt_string_list ["/User/any-project"; "/User/nested/any-project"] (sort_matches input)
	);

	test "sort_matches: prioritizes shortest path on equal depth" (fun expect ->
	  let input = ["/User/nested_longest/any-project"; "/User/short/any-project"] in
	  expect.equal fmt_string_list ["/User/short/any-project"; "/User/nested_longest/any-project"] (sort_matches input)
	);

	test "sort_matches: falls back to alphabetical order on equal depth and length" (fun expect ->
	  let input = ["/User/t/any-project"; "/User/a/any-project"] in
	  expect.equal fmt_string_list ["/User/a/any-project"; "/User/t/any-project"] (sort_matches input)
	)
)
