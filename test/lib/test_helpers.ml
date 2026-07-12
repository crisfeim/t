open Test_lib
open T.Logic
open T.Parser

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
  | Error (`ProjectNotFound proj) -> "Error `ProjectNotFound: " ^ proj

let case_id i = Printf.sprintf "Matrix Case %d" (i + 1)

(* Formatters *)
let fmt_result_list result    = string_of_result (fun l -> "[" ^ String.concat "; " l ^ "]") result
let fmt_result_string result  = string_of_result (fun s -> "\"" ^ s ^ "\"") result
let fmt_result_unit result    = string_of_result (fun _ -> "()") result

let fmt_string str = str
let fmt_string_list l = "[" ^ (String.concat "; " (List.map (fun s -> "\"" ^ s ^ "\"") l)) ^ "]"
let fmt_string_list_of_list l = "[" ^ (String.concat "; " (List.map fmt_string_list l)) ^ "]"

let fmt_tuple tuple =
  let fmt_tuple (path, tasks) = Printf.sprintf "(\"%s\", %s)" path (fmt_string_list tasks) in
  "[" ^ (String.concat "; " (List.map fmt_tuple tuple)) ^ "]"

let fmt_option fmt = function
  | None -> "None"
  | Some cmd -> "Some (" ^ fmt cmd ^ ")"


let fmt_int_list l = "[" ^ (String.concat "; " (List.map string_of_int l)) ^ "]"

let fmt_command = function
	| Count -> "Count"
  | List p -> Printf.sprintf "List %S" p
  | ListRange (p, l) -> Printf.sprintf "ListRange (%S, %s)" p (fmt_int_list l)
  | Add (p, s) -> Printf.sprintf "Add (%S, %S)" p s
  | Complete (p, l) -> Printf.sprintf "Complete (%S, %s)" p (fmt_int_list l)
  | Remove (p, l) -> Printf.sprintf "Remove (%S, %s)" p (fmt_int_list l)
  | Edit (p, i) -> Printf.sprintf "Edit (%S, %d)" p i
  | Update (p, i, v) -> Printf.sprintf "Update (%S, %d, %S)" p i v
  | Commit (p, i, b) -> Printf.sprintf "Commit (%S, %d, %b)" p i b
  | Echo (p, i) -> Printf.sprintf "Echo (%S, %d)" p i
  | EditFile p -> Printf.sprintf "EditFile %S" p
  | Doing (p, i) -> Printf.sprintf "Doing (%S, %d)" p i
  | ListDoing p -> Printf.sprintf "ListDoing %S" p
  | ListProjects -> "ListProjects"
  | ListDoingAcrossProjects -> "ListDoingAcrossProjects"

let fmt_result_projects_doing result =
  match result with
  | Error `FileSystem -> "Error FileSystem"
  | Error `Editor -> "Error Editor"
  | Error `NoRepository -> "Error NoRepository"
  | Error (`CommitError msg) -> "Error CommitError: " ^ msg
  | Error (`WrongLine n) -> Printf.sprintf "Error WrongLine %d" n
  | Ok projects ->
    projects
    |> List.map (fun (path, doings) ->
         Printf.sprintf "%s:\n%s" path
           (doings |> List.map (fun d -> "  " ^ d) |> String.concat "\n"))
    |> String.concat "\n"

let fmt_result_command result =
  match result with
  | Ok cmd -> "Ok (" ^ fmt_command cmd ^ ")"
  | Error `FileSystem -> "Error FileSystem"
  | Error (`ProjectNotFound name) -> Printf.sprintf "Error (ProjectNotFound %S)" name
