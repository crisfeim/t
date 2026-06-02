import Testing
import Foundation
@testable import t

@Suite class TodoTests {
	
	lazy var tmp = FileManager.default.temporaryDirectory.appendingPathComponent("t-tests—\(UUID().uuidString)").path
	lazy var todo_path = tmp + "/.tasks.txt"
	lazy var done_path = tmp + "/.tasks.done"
	
	init() {
		try! FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
	}
	
	deinit {
		try? FileManager.default.removeItem(atPath: tmp)
	}
	
	@Test func `Adds a new todo item to the file`() throws {
		try add("first", fpath: todo_path)
		try add("second", fpath: todo_path)
		
		let lines = IO.read(todo_path)
		#expect(lines == ["first", "second"])
	}
	
	@Test func `Parses todos while skipping empty lines`() {
		let todos = Todo.parse(from: ["first", "", "third"])
		#expect(todos == [
			Todo.t(line: 1, text: "first", indent: 0, has_children: false),
			Todo.t(line: 3, text: "third", indent: 0, has_children: false)
		])
	}
	
	@Test func `Removes a specific line from the todo file`() throws {
		try IO.write(["first", "second", "third"], to: todo_path)
		let removed = try remove(2, from: todo_path)
		#expect(removed == "second")
		
		let lines = IO.read(todo_path)
		#expect(lines == ["first", "third"])
	}
	
	@Test func `Adds a nested todo item after its parent's children`() throws {
		try IO.write(["parent", "\tchild", "sibling"], to: todo_path)
		try add_nested("new child", after: 1, fpath: todo_path)
		
		let lines = IO.read(todo_path)
		#expect(lines == ["parent", "\tchild", "\tnew child", "sibling"])
	}
	
	@Test func `Double indents a nested child todo item`() throws {
		try IO.write(["parent", "\tchild"], to: todo_path)
		try add_nested("grandchild", after: 2, fpath: todo_path)
		
		let lines = IO.read(todo_path)
		#expect(lines == ["parent", "\tchild", "\t\tgrandchild"])
	}
	
	@Test func `Appends completed tasks to the done file`() {
		add_to_done("first task", fpath: done_path)
		add_to_done("second task", fpath: done_path)
		
		let lines = IO.read(done_path)
		#expect(lines.count == 2)
		#expect(lines.first?.hasSuffix("  first task") ?? false)
		#expect(lines.last?.hasSuffix("  second task") ?? false)
		#expect(lines.first?.prefix(14).allSatisfy({ $0.isNumber }) ?? false)
	}
	
	@Test func `Removes a line and then adds a new todo starting at line 1`() throws {
		try add("first", fpath: todo_path)
		_ = try remove(1, from: todo_path)
		try add("second", fpath: todo_path)
		
		let lines = IO.read(todo_path)
		#expect(lines == ["second"])
	}
	
	@Test func `Moves a completed todo to the done file and removes it from tasks`() throws {
		try IO.write(["first", "second"], to: todo_path)
		try complete_todo(line: 1, launch_editor: false, todo_fpath: todo_path, done_fpath: done_path, repo: nil)
		
		let remaining = IO.read(todo_path)
		#expect(remaining == ["second"])
		
		let done = IO.read(done_path)
		#expect(done.first?.hasSuffix("  first") == true)
	}
}


@Suite struct TodoTests_2 {
	@Test func `Lists todos while skipping child items`() {
		let list = Todo.list(from: [
			"First todo",
			"\tChild 1",
			"\tChild 2",
			"Second todo",
			"\tChild 1",
			"\tChild 2",
			"Third todo"
		])
		
		#expect(list == [
			"1* First todo",
			"4* Second todo",
			"7 Third todo"
		])
	}
	
	@Test func `Lists child items of a specific parent todo`() {
		let todos = [
			"First todo",
			"\tChild 1",
			"\tChild 2",
			"Second todo",
			"\tChild 1",
			"\tChild 2",
			"Third todo"
		]
		
		let childs_1 = Todo.list_childs(of: 1, todos: todos)
		let childs_2 = Todo.list_childs(of: 4, todos: todos)
		let childs_3 = Todo.list_childs(of: 7, todos: todos)
		
		#expect(childs_1 == [
			"2 Child 1",
			"3 Child 2"
		])
		
		#expect(childs_2 == [
			"5 Child 1",
			"6 Child 2"
		])
		
		#expect(childs_3.isEmpty)
	}
}

// MARK: - remove / complete -f / remove -r
extension TodoTests {
	
	// MARK: Unit – Todo.remove
	
	@Test func `Removing parent cascades to direct children`() throws {
		let lines  = ["parent", "\tchild1", "\tchild2", "sibling"]
		let (result, removed) = try Todo.remove(1, from: lines)
		#expect(removed == "parent")
		#expect(result  == ["sibling"])
	}
	
	@Test func `Removing parent cascades to deep descendants`() throws {
		let lines  = ["parent", "\tchild", "\t\tgrandchild", "sibling"]
		let (result, removed) = try Todo.remove(1, from: lines)
		#expect(removed == "parent")
		#expect(result  == ["sibling"])
	}
	
	@Test func `Removing a leaf node deletes only that single line`() throws {
		let lines  = ["parent", "\tchild1", "\tchild2"]
		let (result, removed) = try Todo.remove(2, from: lines)
		#expect(removed == "child1")
		#expect(result  == ["parent", "\tchild2"])
	}
	
	@Test func `Removing a flat node deletes only that line`() throws {
		let lines = ["first", "second", "third"]
		let (result, removed) = try Todo.remove(2, from: lines)
		#expect(removed == "second")
		#expect(result  == ["first", "third"])
	}
	
	@Test func `Removing an out of bounds line throws an error`() throws {
		let lines = ["only line"]
		#expect(throws: Todo.WrongLineNumber.self) {
			try Todo.remove(99, from: lines)
		}
	}
	
	// MARK: Integration – remove -r strips children from file
	
	@Test func `Remove flag deletes parent and cascades to all children in file`() throws {
		try IO.write(["parent", "\tchild1", "\tchild2", "sibling"], to: todo_path)
		let removed = try remove(1, from: todo_path)
		#expect(removed == "parent")
		#expect(IO.read(todo_path) == ["sibling"])
	}
	
	@Test func `Remove flag deletes only the targeted flat node in file`() throws {
		try IO.write(["first", "second", "third"], to: todo_path)
		let removed = try remove(2, from: todo_path)
		#expect(removed == "second")
		#expect(IO.read(todo_path) == ["first", "third"])
	}
	
	// MARK: Integration – complete -f moves parent to done and removes children
	
	@Test func `Completing parent logs parent and purges its tree from tasks`() throws {
		try IO.write(["parent", "\tchild1", "\tchild2", "sibling"], to: todo_path)
		try complete_todo(line: 1, launch_editor: false, todo_fpath: todo_path, done_fpath: done_path, repo: nil)
		
		#expect(IO.read(todo_path) == ["sibling"])
		
		let done = IO.read(done_path)
		#expect(done.count == 1)
		#expect(done.first?.hasSuffix("  parent") == true)
	}
	
	@Test func `Completing a leaf logs it and leaves other tasks intact`() throws {
		try IO.write(["parent", "\tchild", "sibling"], to: todo_path)
		try complete_todo(line: 2, launch_editor: false, todo_fpath: todo_path, done_fpath: done_path, repo: nil)
		
		#expect(IO.read(todo_path) == ["parent", "sibling"])
		
		let done = IO.read(done_path)
		#expect(done.count == 1)
		#expect(done.first?.hasSuffix("  child") == true)
	}
	
	@Test func `Completing parent logs parent and purges deep descendants from tasks`() throws {
		try IO.write(["parent", "\tchild", "\t\tgrandchild", "sibling"], to: todo_path)
		try complete_todo(line: 1, launch_editor: false, todo_fpath: todo_path, done_fpath: done_path, repo: nil)
		
		#expect(IO.read(todo_path) == ["sibling"])
		
		let done = IO.read(done_path)
		#expect(done.count == 1)
		#expect(done.first?.hasSuffix("  parent") == true)
	}
}

extension TodoTests {
	@Test func `Gets high level list`() throws {
		
		let resolvedTmp = URL(fileURLWithPath: tmp).resolvingSymlinksInPath().path
		
		try create_list(["first", "second"], at: "list/1")
		try create_list(["do something"], at: "list/nested/1")
		try create_list(["another list"], at: "another/1")
		
		#expect(Todo.get_all(from: resolvedTmp) == [
			Todo.p(path: "another/1", todos: ["1 another list"]),
			Todo.p(path: "list/1", todos: ["1 first", "2 second"]),
			Todo.p(path: "list/nested/1", todos: ["1 do something"])
		])
	}
	
	private func create_list(_ list: [String], at dir_path: String) throws  {
		let path = tmp + "/" + dir_path + "/.tasks"
		try FileManager.default.createDirectory(atPath: tmp + "/" + dir_path, withIntermediateDirectories: true)
		try IO.write(list, to: path)
	}
}

