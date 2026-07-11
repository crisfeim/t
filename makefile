build:
	dune build

.PHONY: test
test: build
	dune test --force
	tclsh test/integration.tcl
