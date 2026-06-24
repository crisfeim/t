compile: 
	swiftc -O -strict-concurrency=minimal -D RELEASE -o t *.swift
	mv t ~/.local/bin/t

test:
	swiftc -strict-concurrency=minimal -D DEBUG -o test_bin *.swift
	./test_bin; status=$$?; rm -f test_bin; exit $$status
