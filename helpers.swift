// MARK: String Helpers

extension String {
    func leftPadded(_ width: Int) -> String {
        let pad = width - self.count
        return pad > 0 ? String(repeating: " ", count: pad) + self : self
    }
}
