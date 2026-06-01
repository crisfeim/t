// The Swift Programming Language
// https://docs.swift.org/swift-book

@main
struct t {
    static func main() {
        
        let args = CommandLine.arguments
        let defaults = UserDefaults.standard
        let editMessage = args.contains("-e")
        
        let repo     = args.contains("-g") ? nil : VCS.get()
        let taskPath = args.contains("-g") ? global.tasks : taskFilePath(repoRoot: repo?.root)
        let donePath = args.contains("-g") ? global.done  : doneFilePath(repoRoot: repo?.root)
        
        if args.count == 1 {
            Todo.list(from: IO.read(taskPath)).forEach(put)
        } else if let line = defaults.string(forKey: "r").flatMap(Int.init) {
            do {
                try removeLine(line, from: taskPath)
            } catch {
                print("error: line \(line) does not exist\n", to:&stderr)
                exit(1)
            }
        } else if let line = defaults.string(forKey: "f").flatMap(Int.init) {
            do {
                try finalizeTodo(
                    lineNumber: line,
                    editMessage: editMessage,
                    taskPath: taskPath,
                    donePath: donePath,
                    repo: repo
                )
            } catch {
                print("error: line \(line) does not exist\n", to:&stderr)
                exit(1)
            }
        } else if let line = defaults.string(forKey: "a").flatMap(Int.init) {
            let text = args.dropFirst().filter { !$0.hasPrefix("-") && Int($0) == nil }.joined(separator: " ")
            if text.isEmpty {
                print("error: no text provided\n", to:&stderr)
                exit(1)
            }
            do {
                try addNestedTodo(text, after: line, taskPath: taskPath)
            } catch {
                print("error: line \(line) does not exist\n", to:&stderr)
                exit(1)
            }
        } else {
            let text = args.dropFirst().filter { !$0.hasPrefix("-") }.joined(separator: " ")
            if !text.isEmpty {
                do {
                    print(try addTodo(text, taskPath: taskPath))
                } catch {
                    print("error: adding failed", to: &stderr)
                    exit(1)
                }
            } else {
                Todo.list(from: IO.read(taskPath)).forEach(put)
            }
        }
    }
}

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

@discardableResult
func addTodo(_ text: String, taskPath: String) throws -> String {
    let lines = IO.read(taskPath) + [text]
    try IO.write(lines, to: taskPath)
    return "\(lines.count) \(text)"
}

func addNestedTodo(_ text: String, after lineNumber: Int, taskPath: String) throws {
    let updated = try Todo.add(text, to: IO.read(taskPath), after: lineNumber)
    try IO.write(updated, to: taskPath)
}

@discardableResult
func removeLine(_ lineNumber: Int, from path: String) throws -> String? {
    let (lines, removed) = try Todo.remove(lineNumber, from: IO.read(path))
    try IO.write(lines, to: path)
    return removed
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

func finalizeTodo(
    lineNumber: Int,
    editMessage: Bool,
    taskPath: String,
    donePath: String,
    repo: (root: String, vcs: String)?
) throws {
    guard let text = try removeLine(lineNumber, from: taskPath) else { return }
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

