compile: 
	swiftc -O -strict-concurrency=minimal -o t t.swift
	mv t ~/.local/bin/t

test:
	swift -strict-concurrency=minimal -D DEBUG t.swift 
clean:
	rm -f t 
