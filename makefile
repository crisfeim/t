compile: 
	swiftc -O -strict-concurrency=minimal -o t *.swift
	mv t ~/.local/bin/t

test:
	swift -strict-concurrency=minimal -D DEBUG *.swift 
clean:
	rm -f t 
