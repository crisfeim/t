compile: 
	swiftc -O -strict-concurrency=minimal -o t t.swift
	mv t ~/.local/bin/t
clean:
	rm -f t 
