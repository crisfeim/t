update:
	dune build
	cp _build/default/bin/main.exe ~/.local/bin/t

build:
	dune build

.PHONY: test
test: build
	dune test --force
	tclsh test/integration.tcl
