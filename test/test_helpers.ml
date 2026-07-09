open Test_lib
open T

(* Test helpers *)
let any_read = (fun _ -> Ok [])
let any_write = (fun _ _ -> Ok ())
let any_now = (fun _ -> "any date")
let any_editor = (fun _ -> Ok "")
let any_commit = (fun _ _ -> Ok ())
let any_repo = Some { path = "any repo dir"; system = "fossil" }
let any_projects = (fun () -> Ok ["any project path"])

let mock_effects () = {
	projects = any_projects;
	read = any_read;
	write = any_write;
	now = any_now;
	editor = any_editor;
	commit = any_commit;
	get_repo = (fun _ -> any_repo);
}

let string_of_result ok_formatter = function
  | Ok value -> "Ok " ^ (ok_formatter value)
  | Error `FileSystem -> "Error `FileSystem"
  | Error `Editor -> "Error `Editor"
  | Error `NoRepository -> "Error `NoRepository"
  | Error (`CommitError msg) -> "Error `CommitError: " ^ msg
  | Error (`WrongLine line) -> "Error `WrongLine: " ^ string_of_int line

let case_id i = Printf.sprintf "Matrix Case %d" (i + 1)

let fmt_result_list result = string_of_result (fun l -> "[" ^ String.concat "; " l ^ "]") result
let fmt_result_string result  = string_of_result (fun s -> "\"" ^ s ^ "\"") result

let assert_result expect string_of_ok expected actual =
	if expected <> actual then
		let fmt = string_of_result string_of_ok in
		expect.fail (Printf.sprintf "Expected (%s) got (%s) instead" (fmt expected) (fmt actual))

let fmt_result_unit result = string_of_result (fun _ -> "()") result
