package require tcltest
namespace import tcltest::*

proc bin_path {} {
	set TEST_DIR [file dirname [file normalize [info script]]]
	set BIN_PATH [file normalize [file join $TEST_DIR ".." _build default bin main]]
  set BIN_PATH "${BIN_PATH}.exe"
  return $BIN_PATH
}

proc exit_1_on_test_failure {} {
	if {$::tcltest::numTests(Failed) > 0} {
    cleanupTests
    exit 1
	}
}

test echo_arguments {Cli should echo argumens} -body {
    set output [exec [bin_path] hello world from ocaml]
} -result {hello world from ocaml}

exit_1_on_test_failure
cleanupTests
