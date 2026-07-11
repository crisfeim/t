build:
	dune build
	cp _build/default/bin/main.exe ~/.local/bin/t

.PHONY: test
test: build
	dune test --force
	tclsh test/integration.tcl
