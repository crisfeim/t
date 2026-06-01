import Foundation
struct StandardError: TextOutputStream, Sendable {
    private static let handle = FileHandle.standardError
    public func write(_ string: String) {
        Self.handle.write(Data(string.utf8))
    }
}

nonisolated(unsafe) var stderr = StandardError()

func renderError(
    file: StaticString,
    line: UInt,
    message: String,
    to stderr: inout StandardError
) {
    print("\(file):\(line): \(message)", to: &stderr)
}

nonisolated(unsafe) var test: String = ""
func assertEqual<Type: Equatable>(
    _ a: Type,
    _ b: Type,
    _ message: String? = nil,
    file: StaticString = #file,
    line: UInt = #line
) {
    if a != b {

        print("❌ " + line.description + " " + test)
        print(message ?? "assert equal failed")
    } else {
        print("✅ " + line.description + " " + test)
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
    test = name
    do {
        try action()
    } catch {
        renderError(file: file, line: line, message: "Error thrown", to: &stderr)
    }
}
