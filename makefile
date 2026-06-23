compile: 
	swiftc -O -o t t.swift
	mv t ~/.local/bin/t
clean:
	rm -f t 
