(* Global state *)
let exit_code = ref 0
let cases: (string * int * int * string list) list ref = ref []

(* Library *)
type expect = {
  is    : bool -> string -> unit;
  equal : 'a. ('a -> string) -> 'a -> 'a -> unit;
  fail  : string -> unit;
}

exception Test_failed

let format_error description message =
  if message = "" then Printf.sprintf "\u{001B}[91m􀢄\u{001B}[0m  %s" description
  else Printf.sprintf "\u{001B}[91m􀢄\u{001B}[0m  %s: %s" description message

let raise_error description message errors_ref =
  errors_ref := format_error description message :: !errors_ref;
  raise Test_failed

let make_expect description errors_ref =
  let is bool message = if bool then () else raise_error description message errors_ref in

  let equal fmt expected actual =
    if expected = actual then ()
    else
      let message = Printf.sprintf "Expected (%s) got (%s) instead" (fmt expected) (fmt actual) in
      raise_error description message errors_ref
  in

  let fail message = raise_error description message errors_ref in

  { is ; equal ; fail }

let case_factory name test_fn =
	let passed = ref 0 in
	let failed = ref 0 in
	let errors = ref [] in
	test_fn (fun description expect_fn ->
	  try expect_fn (make_expect description errors); passed := !passed + 1;
	  with
	    | Test_failed -> (); failed := !failed + 1;
	    | exn ->
	      errors := format_error description ("Failed: " ^ Printexc.to_string exn) :: !errors;
	      failed := !failed + 1;
	);
	if !failed > 0 then exit_code := 1;
	(name, !passed, !failed, !errors)

let case name fn = cases := (case_factory name fn) :: !cases

let run_cases cases =
	let max_name_len = List.fold_left (fun acc (name, _, _, _) -> max acc (String.length name)) 0 cases in
  cases |> List.iter (fun (name, passed, failed, errors) ->
    Printf.printf "\u{001B}[1m%-*s\u{001B}[0m | \u{001B}[92mPassed: %2d\u{001B}[0m | \u{001B}[91mFailed: %2d\u{001B}[0m" max_name_len name passed failed;
    if errors <> [] then begin
      print_newline ();
      List.iter print_endline (List.rev errors);
      print_newline ()
    end else
      print_newline ()
  )

let on_exit () =
	let total_passed, total_failed =
    List.fold_left
      (fun (acc_p, acc_f) (_, passed, failed, _) -> (acc_p + passed, acc_f + failed))
      (0, 0)
      !cases
  in

  let all_case = ("All tests", total_passed, total_failed, []) in

	run_cases (all_case :: !cases);
	let exit_code = if total_failed > 0 then 1 else 0 in
  exit exit_code

let () = at_exit (on_exit)
