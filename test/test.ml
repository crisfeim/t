(* Test utility *)
[@@@warning "-69"]
[@@@warning "-32"]
type expect = {
  is    : bool -> string -> unit;
  equal : 'a. 'a -> 'a -> unit;
  fail  : string -> unit;
}
let format_error description message =
  if message = "" then Printf.sprintf "\u{001B}[91m􀢄\u{001B}[0m  %s" description
  else Printf.sprintf "\u{001B}[91m􀢄\u{001B}[0m  %s: %s" description message

exception Test_failed

let raise_error description message errors_ref =
  errors_ref := format_error description message :: !errors_ref;
  raise Test_failed

let make_expect description errors_ref =
  let is bool message = if bool then () else raise_error description message errors_ref in
  { is;
    equal = (fun expected actual ->
      if expected = actual then ()
      else raise_error description "" errors_ref);
    fail = (fun message -> raise_error description message errors_ref) }

let exit_code = ref 0

let case name fn =
  let passed = ref 0 in
  let failed = ref 0 in
  let errors = ref [] in
  fn (fun description fn ->
    try fn (make_expect description errors); passed := !passed + 1;
    with
      | Test_failed -> (); failed := !failed + 1;
      | exn ->
        errors := format_error description ("Failed: " ^ Printexc.to_string exn) :: !errors;
        failed := !failed + 1;
  );
  if !failed > 0 then exit_code := 1;

  Printf.printf "\u{001B}[1m%-20s\u{001B}[0m | \u{001B}[92mPassed: %2d\u{001B}[0m | \u{001B}[91mFailed: %2d\u{001B}[0m" name !passed !failed;
  if !errors <> [] then begin
    print_newline ();
    List.iter print_endline (List.rev !errors);
    print_newline ()
  end else
    print_newline ()

let () = at_exit (fun () -> exit !exit_code)
