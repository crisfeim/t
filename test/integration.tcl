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

proc read_file {file} {
	set file_handle [open $file r]
	set file_content [read -nonewline $file_handle]
	close $file_handle
	return $file_content
}

proc t {test_dir args} {
	exec -keepnewline sh -c "cd '$test_dir' && '[bin_path]' $args"
}

test list_todos {List local todos when empty args} -setup {
    set test_dir [exec mktemp -d]

    set todo_file [file join $test_dir ".todo"]
    set fh [open $todo_file w]
    puts $fh "lavar la ropa"
    puts $fh "comprar leche"
    close $fh
} -body {
	t $test_dir
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
  t $test_dir count
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
	t $test_dir 1...2
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
	 t $test_dir 1
} -cleanup {
	if {[file exists $todo_file]} { file delete -force $todo_file }
} -result "1 A\n"

test add_todo {Adds todo to local .todo file} -setup {
    set test_dir [exec mktemp -d]
    set todo_file [file join $test_dir ".todo"]
    close [open $todo_file w]
} -body {
    set output [t $test_dir New todo]
    set file_content [read_file $todo_file]

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
    set output [t $test_dir -1]
    set file_content [read_file $todo_file]
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
	set output [t $test_dir +1]
	set todo_file_content [read_file $todo_file]
	set done_file_content [read_file $done_file]
	set has_todo_in_done [regexp {A} $done_file_content]

  list $output $todo_file_content $has_todo_in_done
} -cleanup {
	if {[file exists $todo_file]} { file delete -force $todo_file }
} -result [list "A\n" "" 1]


proc make_fake_editor {test_dir content} {
    set editor_script [file join $test_dir "fake_editor.sh"]
    set fh [open $editor_script w]
    puts $fh {#!/bin/sh}
    puts $fh "echo \"$content\" > \"\$1\""
    close $fh
    file attributes $editor_script -permissions 0755
    return $editor_script
}

test edit_todo {Edits a todo via $EDITOR} -setup {
    set test_dir [exec mktemp -d]
    set todo_file [file join $test_dir ".todo"]
    set fh [open $todo_file w]
    puts $fh "Sacar al perro a pasear"
    close $fh

    set editor_override [make_fake_editor $test_dir "Pasear al perro por el parque"]
} -body {
    global env
    set env(EDITOR) $editor_override
    set output [t $test_dir :1]
    set todo_file_content [read_file $todo_file]
    list $output $todo_file_content
} -cleanup {
    unset -nocomplain env(EDITOR)
    file delete -force $test_dir
} -result [list "Pasear al perro por el parque\n" "Pasear al perro por el parque"]


test edit_cancels_on_empty_edit {Edits a todo via $EDITOR} -setup {
    set test_dir [exec mktemp -d]
    set todo_file [file join $test_dir ".todo"]
    set fh [open $todo_file w]
    puts $fh "Sacar al perro a pasear"
    close $fh

    set editor_override [make_fake_editor $test_dir ""]
} -body {
    global env
    set env(EDITOR) $editor_override
    set output [t $test_dir :1]
    set todo_file_content [read_file $todo_file]
    list $output $todo_file_content
} -cleanup {
    unset -nocomplain env(EDITOR)
    file delete -force $test_dir
} -result [list "Cancel editing\n" "Sacar al perro a pasear"]


test edit_cancels_on_unchanged_edit {Edits a todo via $EDITOR} -setup {
    set test_dir [exec mktemp -d]
    set todo_file [file join $test_dir ".todo"]
    set fh [open $todo_file w]
    puts $fh "Sacar al perro a pasear"
    close $fh

    set editor_override [make_fake_editor $test_dir "Sacar al perro a pasear"]
} -body {
    global env
    set env(EDITOR) $editor_override
    set output [t $test_dir :1]
    set todo_file_content [read_file $todo_file]
    list $output $todo_file_content
} -cleanup {
    unset -nocomplain env(EDITOR)
    file delete -force $test_dir
} -result [list "Cancel editing\n" "Sacar al perro a pasear"]


proc setup_fossil_repo {repo_file test_dir} {
    exec fossil init $repo_file
    exec sh -c "cd '$test_dir' && fossil open '$repo_file'"
}

test commit_todo {Commits a todo to fossil, archives it, empties .todo} -setup {
    set repo_dir [exec mktemp -d]
    set test_dir [exec mktemp -d]
    set repo_file [file join $repo_dir "repo.fossil"]
    setup_fossil_repo $repo_file $test_dir

    set todo_file [file join $test_dir ".todo"]
    set done_file [file join $test_dir ".done"]
    set fh [open $todo_file w]
    puts $fh "dummy todo content"
    close $fh

    #  Add fake work so we avoid 'nothing has changed' errors
    set work_file [file join $test_dir "work.txt"]
    set fh [open $work_file w]
    puts $fh "some project change"
    close $fh
} -body {

    t $test_dir c1 2>@1

    set todo_file_content [read_file $todo_file]
    set done_file_content [read_file $done_file]
    set has_todo_in_done [regexp {dummy todo content} $done_file_content]

    set commit_count [exec sh -c "cd '$test_dir' && fossil sql \"SELECT count(*) FROM event WHERE type='ci';\" 2>/dev/null"]
    set commit_msg [exec sh -c "cd '$test_dir' && fossil sql \"SELECT comment FROM event WHERE type='ci';\" 2>/dev/null"]
    set has_correct_commit_msg [regexp {dummy todo content} $commit_msg]

    list $todo_file_content $has_todo_in_done $commit_count $has_correct_commit_msg

} -cleanup {
    file delete -force $repo_dir
    file delete -force $test_dir
} -result [list "" 1 2 1]


exit_1_on_test_failure
cleanupTests
