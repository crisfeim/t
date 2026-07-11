#!/opt/homebrew/bin/tclsh
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

test list_todos {List local todos when empty args} -setup {
    set test_dir [exec mktemp -d]

    set todo_file [file join $test_dir ".todo"]
    set fh [open $todo_file w]
    puts $fh "lavar la ropa"
    puts $fh "comprar leche"
    close $fh
} -body {
    set output [exec -keepnewline sh -c "cd '$test_dir' && '[bin_path]'"]
} -cleanup {
    if {[file exists $todo_file]} { file delete -force $todo_file }
} -result "1 comprar leche\n2 lavar la ropa\n"

exit_1_on_test_failure
cleanupTests
