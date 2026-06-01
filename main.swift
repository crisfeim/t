import Foundation
struct StandardError: TextOutputStream, Sendable {
    private static let handle = FileHandle.standardError
    public func write(_ string: String) {
        Self.handle.write(Data(string.utf8))
    }
}

var stderr = StandardError()

func renderError(
    file: StaticString,
    line: UInt,
    message: String,
    to stderr: inout StandardError
) {
    print("\(file):\(line): \(message)", to: &stderr)
}

func assertEqual<Type: Equatable>(
    _ a: Type,
    _ b: Type,
    _ message: String? = nil,
    file: StaticString = #file,
    line: UInt = #line
) {
    if a != b {
        renderError(
            file: file,
            line: line,
            message: message ?? "assert equal failed",
            to: &stderr
        )
    }
}

func fail(_ message: String, file: StaticString = #file, line: UInt = #line) {
    renderError(
        file: file,
        line: line,
        message: message,
        to: &stderr
    )
}

func test(_ name: String, file: StaticString = #file, line: UInt = #line, action: () throws -> Void) {
    do {
        try action()
    } catch {
        renderError(file: file, line: line, message: "Error thrown", to: &stderr)
    }
}