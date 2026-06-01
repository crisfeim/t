import Foundation
import Darwin

// MARK: Types

struct Todo {
    let lineNumber: Int
    let text: String
    let indent: Int

    var textWithoutIndent: String { text.trimmingCharacters(in: .whitespaces) }
}

// MARK: VCS Detection

func findRepoRoot(from path: String) -> (root: String, vcs: String)? {
    let fm = FileManager.default
    var current = path
    while true {
        if fm.fileExists(atPath: current + "/.git") { return (current, "git") }
        if fm.fileExists(atPath: current + "/fslckout") { return (current, "fossil") }
        let parent = (current as NSString).deletingLastPathComponent
        if parent == current { return nil }
        current = parent
    }
}

func currentVCS() -> (root: String, vcs: String)? {
    findRepoRoot(from: FileManager.default.currentDirectoryPath)
}

// MARK: File Paths

func taskFilePath(repoRoot: String? = nil) -> String {
    if let root = repoRoot ?? currentVCS()?.root {
        return root + "/tasks"
    }
    return NSHomeDirectory() + "/.tasks"
}

func doneFilePath(repoRoot: String? = nil) -> String {
    if let root = repoRoot ?? currentVCS()?.root {
        return root + "/.tasks.done"
    }
    return NSHomeDirectory() + "/.tasks.done"
}

// MARK: Read / Write

func readLines(from path: String) -> [String] {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    var lines = content.components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    return lines
}

func writeLines(_ lines: [String], to path: String) {
    let content = lines.joined(separator: "\n") + "\n"
    try? content.write(toFile: path, atomically: true, encoding: .utf8)
}

func parseTodos(from lines: [String]) -> [Todo] {
    lines.enumerated().compactMap { i, line in
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let indent = line.prefix(while: { $0 == "\t" }).count
        return Todo(lineNumber: i + 1, text: line, indent: indent)
    }
}

// MARK: Actions

func listTodos(taskPath: String) {
    let lines = readLines(from: taskPath)
    let todos = parseTodos(from: lines)
    if todos.isEmpty {
        print("No todos.")
        return
    }
    let width = String(todos.map { $0.lineNumber }.max() ?? 1).count
    for todo in todos {
        print("\(String(todo.lineNumber).leftPadded(width))  \(todo.text)")
    }
}

func addTodo(_ text: String, taskPath: String) {
    var lines = readLines(from: taskPath)
    lines.append(text)
    writeLines(lines, to: taskPath)
}

func addNestedTodo(_ text: String, after lineNumber: Int, taskPath: String) {
    var lines = readLines(from: taskPath)
    guard lineNumber >= 1 && lineNumber <= lines.count else {
        print("error: line \(lineNumber) does not exist\n", to:&stderr)
        exit(1)
    }

    let refIndex = lineNumber - 1
    let refIndent = lines[refIndex].prefix(while: { $0 == "\t" }).count
    let newLine = String(repeating: "\t", count: refIndent + 1) + text

    var insertIndex = refIndex + 1
    while insertIndex < lines.count {
        let line = lines[insertIndex]
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            insertIndex += 1
            continue
        }
        if line.prefix(while: { $0 == "\t" }).count <= refIndent { break }
        insertIndex += 1
    }

    lines.insert(newLine, at: insertIndex)
    writeLines(lines, to: taskPath)
}

@discardableResult
func removeLine(_ lineNumber: Int, from path: String) -> String? {
    var lines = readLines(from: path)
    guard lineNumber >= 1 && lineNumber <= lines.count else {
        print("error: line \(lineNumber) does not exist\n", to: &stderr)
        exit(1)
    }
    let removed = lines.remove(at: lineNumber - 1)
    writeLines(lines, to: path)
    return removed.trimmingCharacters(in: .whitespaces)
}

func appendToDone(_ text: String, donePath: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMddHHmmss"
    let line = "\(formatter.string(from: Date()))  \(text)\n"
    if let handle = FileHandle(forWritingAtPath: donePath) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        try? line.write(toFile: donePath, atomically: true, encoding: .utf8)
    }
}

func finalizeTodo(lineNumber: Int, editMessage: Bool, taskPath: String, donePath: String, repo: (root: String, vcs: String)?) {
    guard let text = removeLine(lineNumber, from: taskPath) else { return }
    appendToDone(text, donePath: donePath)

    guard let repo = repo else { return }

    let tmpDir = FileManager.default.temporaryDirectory.path

    if editMessage {
        let commitMsgFile = tmpDir + "/t_commit_msg"
        try? text.write(toFile: commitMsgFile, atomically: true, encoding: .utf8)

        let script: String
        if repo.vcs == "fossil" {
            script = """
            cd \(repo.root)
            vi \(commitMsgFile)
            fossil addremove
            fossil commit -M \(commitMsgFile) --allow-empty
            rm \(commitMsgFile)
            """
        } else {
            script = """
            cd \(repo.root)
            vi \(commitMsgFile)
            git add -A
            git commit -F \(commitMsgFile)
            rm \(commitMsgFile)
            """
        }

        let scriptPath = tmpDir + "/t_commit.sh"
        try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)

        execve("/bin/zsh", [strdup("/bin/zsh"), strdup(scriptPath), nil], environ)
    } else {
        let cmd: String
        if repo.vcs == "fossil" {
            cmd = "cd \(repo.root) && fossil addremove && fossil commit -m \"\(text)\" --allow-empty"
        } else {
            cmd = "cd \(repo.root) && git add -A && git commit -m \"\(text)\""
        }
        execve("/bin/zsh", [strdup("/bin/zsh"), strdup("-c"), strdup(cmd), nil], environ)
    }
}

// MARK: String Helpers

extension String {
    func leftPadded(_ width: Int) -> String {
        let pad = width - self.count
        return pad > 0 ? String(repeating: " ", count: pad) + self : self
    }
}

// MARK: Tests

func runTests() {
    let fm = FileManager.default
    let tmpDir = fm.temporaryDirectory.appendingPathComponent("t-tests").path

    test("addTodo appends to file") {
        try? fm.removeItem(atPath: tmpDir)
        try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        let path = tmpDir + "/tasks"
        addTodo("first", taskPath: path)
        addTodo("second", taskPath: path)

        let lines = readLines(from: path)
        assertEqual(lines.count, 2)
        assertEqual(lines[0], "first")
        assertEqual(lines[1], "second")
    }

    test("parseTodos skips empty lines and tracks line numbers") {
        let lines = ["first", "", "third"]
        let todos = parseTodos(from: lines)
        assertEqual(todos.count, 2)
        assertEqual(todos[0].lineNumber, 1)
        assertEqual(todos[0].text, "first")
        assertEqual(todos[1].lineNumber, 3)
        assertEqual(todos[1].text, "third")
    }

    test("removeLine removes correct line") {
        try? fm.removeItem(atPath: tmpDir)
        try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        let path = tmpDir + "/tasks"
        writeLines(["first", "second", "third"], to: path)
        let removed = removeLine(2, from: path)
        assertEqual(removed, "second")
        let lines = readLines(from: path)
        assertEqual(lines.count, 2)
        assertEqual(lines[0], "first")
        assertEqual(lines[1], "third")
    }

    test("addNestedTodo inserts after children") {
        try? fm.removeItem(atPath: tmpDir)
        try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        let path = tmpDir + "/tasks"
        writeLines(["parent", "\tchild", "sibling"], to: path)
        addNestedTodo("new child", after: 1, taskPath: path)

        let lines = readLines(from: path)
        assertEqual(lines.count, 4)
        assertEqual(lines[0], "parent")
        assertEqual(lines[1], "\tchild")
        assertEqual(lines[2], "\tnew child")
        assertEqual(lines[3], "sibling")
    }

    test("addNestedTodo double indents nested child") {
        try? fm.removeItem(atPath: tmpDir)
        try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        let path = tmpDir + "/tasks"
        writeLines(["parent", "\tchild"], to: path)
        addNestedTodo("grandchild", after: 2, taskPath: path)

        let lines = readLines(from: path)
        assertEqual(lines.count, 3)
        assertEqual(lines[2], "\t\tgrandchild")
    }

    test("appendToDone creates file and appends") {
        try? fm.removeItem(atPath: tmpDir)
        try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        let path = tmpDir + "/.tasks.done"
        appendToDone("first task", donePath: path)
        appendToDone("second task", donePath: path)

        let lines = readLines(from: path)
        assertEqual(lines.count, 2)
        assertEqual(lines[0].hasSuffix("  first task"), true)
        assertEqual(lines[1].hasSuffix("  second task"), true)
        assertEqual(lines[0].prefix(14).allSatisfy({ $0.isNumber }), true)
    }

    test("finalizeTodo moves to done and removes from tasks") {
        try? fm.removeItem(atPath: tmpDir)
        try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        let taskPath = tmpDir + "/tasks"
        let donePath = tmpDir + "/.tasks.done"
        writeLines(["first", "second"], to: taskPath)
        finalizeTodo(lineNumber: 1, editMessage: false, taskPath: taskPath, donePath: donePath, repo: nil)

        let remaining = readLines(from: taskPath)
        assertEqual(remaining.count, 1)
        assertEqual(remaining[0], "second")

        let done = readLines(from: donePath)
        assertEqual(done.count, 1)
        assertEqual(done[0].hasSuffix("  first"), true)
    }

    test("fossil integration") {
        let fm = FileManager.default
        let repoDir = fm.temporaryDirectory.appendingPathComponent("t-fossil-tests").path
        try? fm.removeItem(atPath: repoDir)
        try! fm.createDirectory(atPath: repoDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repoDir) }

        runCommand("fossil init repo.fossil", inDirectory: repoDir)
        runCommand("fossil open repo.fossil", inDirectory: repoDir)

        let taskPath = repoDir + "/tasks"
        let donePath = repoDir + "/.tasks.done"
        writeLines(["fix bug", "write docs"], to: taskPath)

        finalizeTodo(lineNumber: 1, editMessage: false, taskPath: taskPath, donePath: donePath, repo: (repoDir, "fossil"))

        let remaining = readLines(from: taskPath)
        assertEqual(remaining.count, 1)
        assertEqual(remaining[0], "write docs")

        let done = readLines(from: donePath)
        assertEqual(done.count, 1)
        assertEqual(done[0].hasSuffix("  fix bug"), true)
    }
}

// MARK: Command

@discardableResult
func runCommand(_ command: String, inDirectory directory: String? = nil) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", command]
    if let dir = directory { process.currentDirectoryURL = URL(fileURLWithPath: dir) }
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try? process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

// MARK: CLI

let args = CommandLine.arguments
let defaults = UserDefaults.standard
let editMessage = args.contains("-e")

if args.contains("--test") {
    runTests()
    exit(0)
}

let repo = currentVCS()
let taskPath = taskFilePath()
let donePath = doneFilePath()

if args.count == 1 {
    listTodos(taskPath: taskPath)
} else if let lineNumber = defaults.string(forKey: "r").flatMap(Int.init) {
    removeLine(lineNumber, from: taskPath)
} else if let lineNumber = defaults.string(forKey: "f").flatMap(Int.init) {
    finalizeTodo(lineNumber: lineNumber, editMessage: editMessage, taskPath: taskPath, donePath: donePath, repo: repo)
} else if let lineNumber = defaults.string(forKey: "a").flatMap(Int.init) {
    let text = args.dropFirst().filter { !$0.hasPrefix("-") && Int($0) == nil }.joined(separator: " ")
    if text.isEmpty {
        print("error: no text provided\n", to:&stderr)
        exit(1)
    }
    addNestedTodo(text, after: lineNumber, taskPath: taskPath)
} else {
    let text = args.dropFirst().filter { !$0.hasPrefix("-") }.joined(separator: " ")
    if !text.isEmpty {
        addTodo(text, taskPath: taskPath)
    } else {
        listTodos(taskPath: taskPath)
    }
}

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
    } else {
        print("✅ " + line.description)
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