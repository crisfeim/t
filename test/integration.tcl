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

test get_count {Delivers local todos total count} -setup {
    set test_dir [exec mktemp -d]

    set todo_file [file join $test_dir ".todo"]
    set fh [open $todo_file w]
    puts $fh "lavar la ropa"
    puts $fh "comprar leche"
    close $fh
} -body {
    set output [exec -keepnewline sh -c "cd '$test_dir' && '[bin_path]' count"]
} -cleanup {
    if {[file exists $todo_file]} { file delete -force $todo_file }
} -result "2\n"

test list_range {Lists a range from local todos} -setup {
	set test_dir [exec mktemp -d]
  set todo_file [file join $test_dir ".todo"]
  set fh [open $todo_file w]
  puts $fh "A"
  puts $fh "B"
  puts $fh "C"
  close $fh
} -body {
	 set output [exec -keepnewline sh -c "cd '$test_dir' && '[bin_path]' 1...2"]
} -cleanup {
	if {[file exists $todo_file]} { file delete -force $todo_file }
} -result "1 C\n2 B\n"

test echo {Echoes line from local .todo} -setup {
	set test_dir [exec mktemp -d]
  set todo_file [file join $test_dir ".todo"]
  set fh [open $todo_file w]
  puts $fh "A"
  close $fh
} -body {
	 set output [exec -keepnewline sh -c "cd '$test_dir' && '[bin_path]' 1"]
} -cleanup {
	if {[file exists $todo_file]} { file delete -force $todo_file }
} -result "1 A\n"

test add_todo {Adds todo to local .todo file} -setup {
    set test_dir [exec mktemp -d]
    set todo_file [file join $test_dir ".todo"]
    close [open $todo_file w]
} -body {
    set output [exec -keepnewline sh -c "cd '$test_dir' && '[bin_path]' 'New todo'"]

    set fh [open $todo_file r]
    set file_content [read -nonewline $fh]
    close $fh

    list $output $file_content
} -cleanup {
    if {[file exists $todo_file]} { file delete -force $todo_file }
} -result [list "New todo\n" "New todo"]

test remove_todo {Removos todo from local .todo file} -setup {
    set test_dir [exec mktemp -d]
    set todo_file [file join $test_dir ".todo"]
    set fh [open $todo_file w]
    puts $fh "A"
    close $fh
} -body {
    set output [exec -keepnewline sh -c "cd '$test_dir' && '[bin_path]' -1"]

    set fh [open $todo_file r]
    set file_content [read -nonewline $fh]
    close $fh

    list $output $file_content
} -cleanup {
    if {[file exists $todo_file]} { file delete -force $todo_file }
} -result [list "A\n" ""]

test complete_todo {Completes a todo from local todos} -setup {
	set test_dir [exec mktemp -d]
  set todo_file [file join $test_dir ".todo"]
  set done_file [file join $test_dir ".done"]
  close [open $done_file w]
  set fh [open $todo_file w]
  puts $fh "A"
  close $fh
} -body {
	set output [exec -keepnewline sh -c "cd '$test_dir' && '[bin_path]' +1"]
	set todo_fh [open $todo_file r]
	set todo_file_content [read -nonewline $todo_fh]
	close $todo_fh

	set done_fh [open $done_file r]
	set done_file_content [read -nonewline $done_fh]
	close $done_fh

	set has_todo_in_done [regexp {A} $done_file_content]

  list $output $todo_file_content $has_todo_in_done
} -cleanup {
	if {[file exists $todo_file]} { file delete -force $todo_file }
} -result [list "A\n" "" 1]

exit_1_on_test_failure
cleanupTests
