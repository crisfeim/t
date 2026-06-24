func assertThrows<E: Error & Equatable>(_ expected: E, _ block: () throws(E) -> Void) {
    do throws(E) {
        try block()
        assert(false)
    } catch {
        assert(error == expected)
    }
}