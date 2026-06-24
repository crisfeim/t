func assertThrows<E: Error & Equatable>(_ expected: E, line: UInt = #line, _ block: () throws(E) -> Void) {
    do throws(E) {
        try block()
        assert(false, line: line)
    } catch {
        assert(error == expected, line: line)
    }
}