// MARK: String Helpers

extension String {
    func leftPadded(_ width: Int) -> String {
        let pad = width - self.count
        return pad > 0 ? String(repeating: " ", count: pad) + self : self
    }
}

var put: (String) -> Void = { print($0) }

infix operator *: MultiplicationPrecedence
func *<A>(lhs: A, rhs: (inout A) -> Void) -> A {
    var copy = lhs
    rhs(&copy)
    return copy
}