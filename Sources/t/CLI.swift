// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import ArgumentParser

struct CLI {
	let r: Int?
	let f: Int?
	let a: Int?
	let l: Int?
	
	let g: Bool
	let e: Bool
	let s: Bool
	
	let args: [String]
	
	func run() throws {
		let repo       = g ? nil : VCS.get()
		let todo_fpath = g ? global.todo : todo_fpath(repo_dir: repo?.dir)
		let done_fpath = g ? global.done : done_fpath(repo_dir: repo?.dir)
		
		if let r { try remove(r, from: todo_fpath) ; return }
		if let f {
			return try complete_todo(
				line: f,
				launch_editor: e,
				todo_fpath: todo_fpath,
				done_fpath: done_fpath,
				repo: repo
			)
		}
		if let a {
			let todo = args.filter { !$0.hasPrefix("-") }.joined(separator: " ")
			if todo.isEmpty { throw ValidationError("no text provided") }
			return try add_nested(todo, after: a, fpath: todo_fpath)
		}
		
		if let l {
			return Todo.list_childs(of: l, todos: IO.read(todo_fpath)).forEach(put)
		}
		
		if s {
			return Todo.get_all(from: NSHomeDirectory()).map(\.path).forEach(put)
		}
		
		let todo = args.filter { !$0.hasPrefix("-") }.joined(separator: " ")
		if !todo.isEmpty { print(try add(todo, fpath: todo_fpath)) }
		else { Todo.list(from: IO.read(todo_fpath)).forEach(put) }
	}
}

@main
struct t: ParsableCommand {
	
	@Option(name: .customShort(.r), help: .r=>help) var r: Int?
	@Option(name: .customShort(.f), help: .f=>help) var f: Int?
	@Option(name: .customShort(.a), help: .a=>help) var a: Int?
	@Option(name: .customShort(.l), help: .l=>help) var l: Int?
	
	@Flag(name: .customShort(.g), help: .g=>help) var g: Bool = false
	@Flag(name: .customShort(.e), help: .e=>help) var e: Bool = false
	@Flag(name: .customShort(.s), help: .s=>help) var s: Bool = false
	
	@Argument(help: "Task text contents.") var args: [String] = []
	
	func run() throws {
		try CLI(r: r, f: f, a: a, l: l, g: g, e: e, s: s, args: args).run()
	}
}

let put: @Sendable (String) -> Void = { print($0) }

import Foundation
import Darwin

// MARK: File Paths

let global = (
	todo: NSHomeDirectory() + "/todo.txt",
	done: NSHomeDirectory() + "/.tasks.done"
)

func todo_fpath(repo_dir: String? = nil) -> String {
	if let root = repo_dir { return root + "/todo.txt" }
	return global.todo
}

func done_fpath(repo_dir: String? = nil) -> String {
	if let root = repo_dir { return root + "/.tasks.done" }
	return global.done
}

@discardableResult
func add(_ todo: String, fpath: String) throws -> String {
	do {
		let lines = IO.read(fpath) + [todo]
		try IO.write(lines, to: fpath)
		return "\(lines.count) \(todo)"
	} catch {
		throw CleanExit.message("error: adding failed")
	}
}

func add_nested(_ text: String, after line: Int, fpath: String) throws {
	do {
		let updated = try Todo.add(text, to: IO.read(fpath), after: line)
		try IO.write(updated, to: fpath)
	} catch {
		throw ValidationError("line \(line) does not exist")
	}
}

@discardableResult
func remove(_ line: Int, from path: String) throws -> String? {
	do {
		let (lines, removed) = try Todo.remove(line, from: IO.read(path))
		try IO.write(lines, to: path)
		return removed
	} catch {
		throw ValidationError("line \(line) does not exist")
	}
}

func add_to_done(_ text: String, fpath: String) {
	let formatter = DateFormatter()
	formatter.dateFormat = "yyyyMMddHHmmss"
	let line = "\(formatter.string(from: Date()))  \(text)\n"
	if let handle = FileHandle(forWritingAtPath: fpath) {
		handle.seekToEndOfFile()
		handle.write(line.data(using: .utf8)!)
		handle.closeFile()
	} else {
		try? line.write(toFile: fpath, atomically: true, encoding: .utf8)
	}
}

func complete_todo(
	line: Int,
	launch_editor: Bool,
	todo_fpath: String,
	done_fpath: String,
	repo: (dir: String, vcs: String)?
) throws {
	guard let text = try remove(line, from: todo_fpath) else { return }
	add_to_done(text, fpath: done_fpath)
	
	guard let repo = repo else { return }
	
	let tmp = FileManager.default.temporaryDirectory.path
	
	if launch_editor {
		let commit_msg_tmp_file = tmp + "/t_commit_msg"
		try? text.write(toFile: commit_msg_tmp_file, atomically: true, encoding: .utf8)
		
		let script: String
		if repo.vcs == "fossil" {
			script = """
			cd \(repo.dir)
			vi \(commit_msg_tmp_file)
			fossil addremove
			fossil commit -M \(commit_msg_tmp_file) --allow-empty
			rm \(commit_msg_tmp_file)
			"""
		} else {
			script = """
			cd \(repo.dir)
			vi \(commit_msg_tmp_file)
			git add -A
			git commit -F \(commit_msg_tmp_file)
			rm \(commit_msg_tmp_file)
			"""
		}
		
		let script_path = tmp + "/t_commit.sh"
		try? script.write(toFile: script_path, atomically: true, encoding: .utf8)
		
		execve("/bin/zsh", [strdup("/bin/zsh"), strdup(script_path), nil], environ)
	} else {
		let cmd: String
		if repo.vcs == "fossil" {
			cmd = "cd \(repo.dir) && fossil addremove && fossil commit -m \"\(text)\" --allow-empty"
		} else {
			cmd = "cd \(repo.dir) && git add -A && git commit -m \"\(text)\""
		}
		execve("/bin/zsh", [strdup("/bin/zsh"), strdup("-c"), strdup(cmd), nil], environ)
	}
}

// MARK: - Commands

private extension Character {
	static let g: Character = "g"
	static let r: Character = "r"
	static let f: Character = "f"
	static let a: Character = "a"
	static let e: Character = "e"
	static let l: Character = "l"
	static let s: Character = "s"
}


private let help: @Sendable (Character) -> ArgumentHelp = {
	switch $0 {
	case "g": return "Use global tasks file if invoked in a local repo"
	case "r": return "Remove a task by line number."
	case "f": return "Finalize and commit a task by line number."
	case "a": return "Add a nested task after the specified line."
	case "e": return "Edit commit message with vi before commiting."
	case "l": return "List the child task of a given line"
	case "s": return "Lists all todos system wide"
	default: return "Unhandled"
	}
}
