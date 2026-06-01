// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import ArgumentParser

@main
struct t: ParsableCommand {

    @Flag(name: .customShort("g"), help: "Use global tasks file if invoked in a local repo")
    var is_global: Bool = false

    @Option(name: .customShort("r"), help: "Remove a task by line number.")
    var line_to_remove: Int?

    @Option(name: .customShort("f"), help: "Finalize and commit a task by line number.")
    var line_to_finalize: Int?

    @Option(name: .customShort("a"), help: "Add a nested task after the specified line.")
    var line_to_append: Int?

    @Flag(name: .customShort("e"), help: "Edit commit message before commiting.")
    var edit_msg: Bool = false

    @Argument(help: "Task text contents.")
    var txt_args: [String] = []

    func run() throws {
        let repo     = is_global ? nil : VCS.get()
        let taskPath = is_global ? global.tasks : taskFilePath(repoRoot: repo?.root)
        let donePath = is_global ? global.done  : doneFilePath(repoRoot: repo?.root)

        if let line_to_remove {
            do {
                try removeLine(line_to_remove, from: taskPath)
            } catch {
                throw ValidationError("line \(line_to_remove) does not exist")
            }
            return
        }

        if let line_to_finalize {
            do {
                try finalizeTodo(
                    lineNumber: line_to_finalize,
                    editMessage: edit_msg,
                    taskPath: taskPath,
                    donePath: donePath,
                    repo: repo
                )
            } catch {
                throw ValidationError("line \(line_to_finalize) does not exist")
            }
            return
        }

        if let line_to_append {
            let text = txt_args.filter { !$0.hasPrefix("-") }.joined(separator: " ")
            if text.isEmpty {
                throw ValidationError("no text provided")
            }
            do {
                try addNestedTodo(text, after: line_to_append, taskPath: taskPath)
            } catch {
                throw ValidationError("line \(line_to_append) does not exist")
            }
            return
        }

        let text = txt_args.filter { !$0.hasPrefix("-") }.joined(separator: " ")
        if !text.isEmpty {
            do {
                print(try addTodo(text, taskPath: taskPath))
            } catch {
                throw CleanExit.message("error: adding failed")
            }
        } else {
            Todo.list(from: IO.read(taskPath)).forEach(put)
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

