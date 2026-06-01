import Foundation
import Darwin


// MARK: File Paths

let global = (
  tasks: NSHomeDirectory() + "/.tasks",
  done: NSHomeDirectory() + "/.tasks.done"
)

func taskFilePath(repoRoot: String? = nil) -> String {
  if let root = repoRoot { return root + "/.tasks" }
  return global.tasks
}

func doneFilePath(repoRoot: String? = nil) -> String {
	if let root = repoRoot { return root + "/.tasks.done" }
  return global.done
}

// MARK: Actions

func listTodos(taskPath: String) {
  Todo.list(from: IO.read(from: taskPath)).forEach(put)
}

func addTodo(_ text: String, taskPath: String) {
	var lines = IO.read(from: taskPath)
	lines.append(text)
	IO.write(lines, to: taskPath)
	print(lines.count, " \(text)")
}

func addNestedTodo(_ text: String, after lineNumber: Int, taskPath: String) {
	var lines = IO.read(from: taskPath)
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
  IO.write(lines, to: taskPath)
}

@discardableResult
func removeLine(_ lineNumber: Int, from path: String) -> String? {
  var lines = IO.read(from: path)
  guard lineNumber >= 1 && lineNumber <= lines.count else {
    print("error: line \(lineNumber) does not exist\n", to: &stderr)
    exit(1)
  }
  let removed = lines.remove(at: lineNumber - 1)
  IO.write(lines, to: path)
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

        let lines = IO.read(from: path)
        assertEqual(lines.count, 2)
        assertEqual(lines[0], "first")
        assertEqual(lines[1], "second")
    }

    test("Todo.parse skips empty lines and tracks line numbers") {
        let lines = ["first", "", "third"]
        let todos = Todo.parse(from: lines)
        assertEqual(todos.count, 2)
        assertEqual(todos[0].line_number, 1)
        assertEqual(todos[0].text, "first")
        assertEqual(todos[1].line_number, 3)
        assertEqual(todos[1].text, "third")
    }

    test("removeLine removes correct line") {
        try? fm.removeItem(atPath: tmpDir)
        try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        let path = tmpDir + "/tasks"
        IO.write(["first", "second", "third"], to: path)
        let removed = removeLine(2, from: path)
        assertEqual(removed, "second")
        let lines = IO.read(from: path)
        assertEqual(lines.count, 2)
        assertEqual(lines[0], "first")
        assertEqual(lines[1], "third")
    }

    test("addNestedTodo inserts after children") {
        try? fm.removeItem(atPath: tmpDir)
        try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        let path = tmpDir + "/tasks"
        IO.write(["parent", "\tchild", "sibling"], to: path)
        addNestedTodo("new child", after: 1, taskPath: path)

        let lines = IO.read(from: path)
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
        IO.write(["parent", "\tchild"], to: path)
        addNestedTodo("grandchild", after: 2, taskPath: path)

        let lines = IO.read(from: path)
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

        let lines = IO.read(from: path)
        assertEqual(lines.count, 2)
        assertEqual(lines[0].hasSuffix("  first task"), true)
        assertEqual(lines[1].hasSuffix("  second task"), true)
        assertEqual(lines[0].prefix(14).allSatisfy({ $0.isNumber }), true)
    }

    test("removeLine then addTodo starts at line 1") {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("t-empty-line-test").path
        try? fm.removeItem(atPath: tmpDir)
        try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        let path = tmpDir + "/tasks"
        addTodo("first", taskPath: path)
        removeLine(1, from: path)
        addTodo("second", taskPath: path)

        let lines = IO.read(from: path)
        assertEqual(lines.count, 1, "Expected 1 line, got \(lines.count)")
        assertEqual(lines[0], "second")
    }

    test("finalizeTodo moves to done and removes from tasks") {
        try? fm.removeItem(atPath: tmpDir)
        try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        let taskPath = tmpDir + "/tasks"
        let donePath = tmpDir + "/.tasks.done"
        IO.write(["first", "second"], to: taskPath)
        finalizeTodo(lineNumber: 1, editMessage: false, taskPath: taskPath, donePath: donePath, repo: nil)

        let remaining = IO.read(from: taskPath)
        assertEqual(remaining.count, 1)
        assertEqual(remaining[0], "second")

        let done = IO.read(from: donePath)
        assertEqual(done.count, 1)
        assertEqual(done[0].hasSuffix("  first"), true)
    }

    test("VCS.root() detects fossil") {
        let fm = FileManager.default
        let repoDir = fm.temporaryDirectory.appendingPathComponent("t-vcs-detection").path
        try? fm.removeItem(atPath: repoDir)
        try! fm.createDirectory(atPath: repoDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repoDir) }

        Runner.run("fossil init repo.fossil", inDirectory: repoDir)
        Runner.run("fossil open repo.fossil", inDirectory: repoDir)

        let result = VCS.root(from: repoDir)
        assertEqual(result?.root, repoDir)
        assertEqual(result?.vcs, "fossil")
    }

    test("fossil integration") {
        let fm = FileManager.default
        let repoDir = fm.temporaryDirectory.appendingPathComponent("t-fossil-tests").path
        try? fm.removeItem(atPath: repoDir)
        try! fm.createDirectory(atPath: repoDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repoDir) }

        Runner.run("fossil init repo.fossil", inDirectory: repoDir)
        Runner.run("fossil open repo.fossil", inDirectory: repoDir)

        let taskPath = repoDir + "/tasks"
        let donePath = repoDir + "/.tasks.done"
        IO.write(["fix bug", "write docs"], to: taskPath)

        finalizeTodo(lineNumber: 1, editMessage: false, taskPath: taskPath, donePath: donePath, repo: (repoDir, "fossil"))

        let remaining = IO.read(from: taskPath)
        assertEqual(remaining.count, 1)
        assertEqual(remaining[0], "write docs")

        let done = IO.read(from: donePath)
        assertEqual(done.count, 1)
        assertEqual(done[0].hasSuffix("  fix bug"), true)
    }

}

// MARK: CLI

let args = CommandLine.arguments
let defaults = UserDefaults.standard
let editMessage = args.contains("-e")

if args.contains("--test") {
    runTests()
    exit(0)
}

let repo     = args.contains("-g") ? nil : VCS.get()
let taskPath = args.contains("-g") ? global.tasks : taskFilePath(repoRoot: repo?.root)
let donePath = args.contains("-g") ? global.done  : doneFilePath(repoRoot: repo?.root)

if args.count == 1 {
    listTodos(taskPath: taskPath)
} else if let line = defaults.string(forKey: "r").flatMap(Int.init) {
    removeLine(line, from: taskPath)
} else if let line = defaults.string(forKey: "f").flatMap(Int.init) {
    finalizeTodo(lineNumber: line, editMessage: editMessage, taskPath: taskPath, donePath: donePath, repo: repo)
} else if let line = defaults.string(forKey: "a").flatMap(Int.init) {
    let text = args.dropFirst().filter { !$0.hasPrefix("-") && Int($0) == nil }.joined(separator: " ")
    if text.isEmpty {
        print("error: no text provided\n", to:&stderr)
        exit(1)
    }
    addNestedTodo(text, after: line, taskPath: taskPath)
} else {
    let text = args.dropFirst().filter { !$0.hasPrefix("-") }.joined(separator: " ")
    if !text.isEmpty {
        addTodo(text, taskPath: taskPath)
    } else {
        listTodos(taskPath: taskPath)
    }
}

