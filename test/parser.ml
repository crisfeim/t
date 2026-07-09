open Test_lib
open T

let ( let*? ) = Option.bind

let to_option = function
  | Ok x -> Some x
  | Error _ -> None
;;

type command =
  | List of path
  | ListRange of path * int list
  | Add of path * string
  | Complete of path * int list
  | Remove of path * int list
  | Edit of path * int
  | Commit of path * int * bool
  | Echo of path * int
  | EditFile of path
  | Doing of path * int
  | ListDoing of path
  | ListProjects
  | ListDoingAcrossProjects

let cmd operator str =
  String.length str > 1
  && String.get str 0 = operator
  && Option.is_some (int_of_string_opt (String.sub str 1 (String.length str - 1)))
;;

let drop n str =
  if n >= String.length str then "" else String.sub str n (String.length str - n)
;;

let is_numeric str = Option.is_some (int_of_string_opt str)

let batch_cmd operator str =
  String.length str > 1
  && String.get str 0 = operator
  && drop 1 str |> String.split_on_char ',' |> List.for_all is_numeric
;;

let is_commit_editing str =
  String.length str > 2 && String.get str 0 = 'c' && String.get str 1 = ':'
;;

let list_from string = String.split_on_char ',' string

let parse_range str =
  match String.split_on_char '.' str with
  | [ left; ""; ""; right ] ->
    (match int_of_string_opt left, int_of_string_opt right with
     | Some left, Some right when right >= left ->
       List.init (right - left + 1) (fun i -> left + i)
     | _ -> [])
  | _ -> []
;;

let parser path args =
  match args with
  | [] -> Some (List path)
  | [ single ] when batch_cmd '+' single ->
    Some (Complete (path, list_from (drop 1 single) |> List.map int_of_string))
  | [ single ] when batch_cmd '-' single ->
    Some (Remove (path, list_from (drop 1 single) |> List.map int_of_string))
  | [ single ] when cmd ':' single -> Some (Edit (path, int_of_string (drop 1 single)))
  | [ single ] when cmd 'c' single ->
    Some (Commit (path, int_of_string (drop 1 single), false))
  | [ single ] when cmd '@' single -> Some (Doing (path, int_of_string (drop 1 single)))
  | [ single ] when is_commit_editing single ->
    let*? line = int_of_string_opt (drop 2 single) in
    Some (Commit (path, line, true))
  | [ single ] when Option.is_some (int_of_string_opt single) ->
    Some (Echo (path, int_of_string single))
  | [ single ] when single = ":" -> Some (EditFile path)
  | [ single ] when single = "@" -> Some (ListDoing path)
  | [ single ] when single = "." -> Some ListProjects
  | [ single ] when single = ".@" -> Some ListDoingAcrossProjects
  | [ single ] when parse_range single <> [] ->
    Some (ListRange (path, parse_range single))
  | values -> Some (Add (path, String.concat " " values))
;;

let command_router todo_path args effects =
  let is_project project =
    String.length project > 1 && String.get project 0 = '.' && String.get project 1 <> '@'
  in
  let project_path name all_projects =
    all_projects
    |> List.filter (fun path ->
      String.split_on_char '/' path |> List.exists (fun part -> part = name))
    |> T.sort_matches
    |> function
    | first :: _ -> Some first
    | [] -> None
  in
  match args with
  | [ project ] when is_project project ->
    let*? all_projects = effects.projects () |> to_option in
    let*? path = project_path (drop 1 project) all_projects in
    Some (List path)
  | [ project; args ] when is_project project ->
    let*? all_projects = effects.projects () |> to_option in
    let*? path = project_path (drop 1 project) all_projects in
    parser path [ args ]
  | values -> parser todo_path args
;;

let any_todo_path = "any-todo-path"

let () =
  case "Parser" (fun test ->
    test "Echo" (fun expect ->
      expect.equal (parser any_todo_path [ "10" ]) (Some (Echo (any_todo_path, 10))));
    test "List" (fun expect ->
      expect.equal (parser any_todo_path []) (Some (List any_todo_path)));
    test "List projects" (fun expect ->
      expect.equal (parser any_todo_path [ "." ]) (Some ListProjects));
    test "List doing across projects" (fun expect ->
      expect.equal (parser any_todo_path [ ".@" ]) (Some ListDoingAcrossProjects));
    test "List range" (fun expect ->
      expect.equal
        (parser any_todo_path [ "1...5" ])
        (Some (ListRange (any_todo_path, [ 1; 2; 3; 4; 5 ]))));
    test "Parse range" (fun expect -> expect.equal (parse_range "1...3") [ 1; 2; 3 ]);
    test "List doing" (fun expect ->
      expect.equal (parser any_todo_path [ "@" ]) (Some (ListDoing any_todo_path)));
    test "Add" (fun expect ->
      expect.equal
        (parser any_todo_path [ "new"; "todo" ])
        (Some (Add (any_todo_path, "new todo"))));
    test "Complete one" (fun expect ->
      expect.equal
        (parser any_todo_path [ "+32" ])
        (Some (Complete (any_todo_path, [ 32 ]))));
    test "Complete many" (fun expect ->
      expect.equal
        (parser any_todo_path [ "+32,24" ])
        (Some (Complete (any_todo_path, [ 32; 24 ]))));
    test "Remove" (fun expect ->
      expect.equal
        (parser any_todo_path [ "-32" ])
        (Some (Remove (any_todo_path, [ 32 ]))));
    test "Remove many" (fun expect ->
      expect.equal
        (parser any_todo_path [ "-32,24" ])
        (Some (Remove (any_todo_path, [ 32; 24 ]))));
    test "Edit" (fun expect ->
      expect.equal (parser any_todo_path [ ":32" ]) (Some (Edit (any_todo_path, 32))));
    test "Edit .todo" (fun expect ->
      expect.equal (parser any_todo_path [ ":" ]) (Some (EditFile any_todo_path)));
    test "Commit" (fun expect ->
      expect.equal
        (parser any_todo_path [ "c32" ])
        (Some (Commit (any_todo_path, 32, false))));
    test "Commit editing" (fun expect ->
      expect.equal
        (parser any_todo_path [ "c:32" ])
        (Some (Commit (any_todo_path, 32, true))));
    test "Mark as doing" (fun expect ->
      expect.equal (parser any_todo_path [ "@32" ]) (Some (Doing (any_todo_path, 32)))))
;;

let () =
  case "Project namespacing" (fun test ->
    let effects =
      { (Test_helpers.mock_effects ()) with
        projects = (fun () -> Ok [ "/User/some-project/.todo" ])
      }
    in
    let cases =
      [ "List", [], Some (List "/User/some-project/.todo")
      ; "Complete", [ "+1,2" ], Some (Complete ("/User/some-project/.todo", [ 1; 2 ]))
      ; "Remove", [ "-5,2" ], Some (Remove ("/User/some-project/.todo", [ 5; 2 ]))
      ; "Edit", [ ":10" ], Some (Edit ("/User/some-project/.todo", 10))
      ; "Doing", [ "@1" ], Some (Doing ("/User/some-project/.todo", 1))
      ; "Commit", [ "c1" ], Some (Commit ("/User/some-project/.todo", 1, false))
      ]
    in
    cases
    |> List.iter (fun (desc, args, expected) ->
      test desc (fun expect ->
        expect.equal
          (command_router any_todo_path ([ ".some-project" ] @ args) effects)
          expected)))
;;
