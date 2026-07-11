package require tcltest
namespace import tcltest::*

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set BIN_PATH [file normalize [file join $SCRIPT_DIR ".." "_build" "default" "bin" "main"]]
if {![file exists $BIN_PATH]} {
    set BIN_PATH "${BIN_PATH}.exe"
}

test echo-arguments {Cli should echo argumens at this point} -body {
    set output [exec $BIN_PATH hello world from ocaml]

    set output
} -result {hello world from ocaml}

if {$::tcltest::numTests(Failed) > 0} {
    cleanupTests
    exit 1
}

cleanupTests
