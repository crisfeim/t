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

	@Test func `addTodoAppendsToFile`() throws {
		try add("first", fpath: todo_path)
		try add("second", fpath: todo_path)

		let lines = IO.read(todo_path)
		#expect(lines == ["first", "second"])
	}

	@Test func `todoParseSkipsEmptyLines`() {
		let todos = Todo.parse(from: ["first", "", "third"])
		#expect(todos == [
			Todo.t(line: 1, text: "first", indent: 0, has_children: false),
			Todo.t(line: 3, text: "third", indent: 0, has_children: false)
		])
	}

	@Test func `removeLineRemovesCorrectLine`() throws {
		try IO.write(["first", "second", "third"], to: todo_path)
		let removed = try remove(2, from: todo_path)
		#expect(removed == "second")

		let lines = IO.read(todo_path)
		#expect(lines == ["first", "third"])
	}

	@Test func `addNestedTodoInsertsAfterChildren`() throws {
		try IO.write(["parent", "\tchild", "sibling"], to: todo_path)
		try add_nested("new child", after: 1, fpath: todo_path)

		let lines = IO.read(todo_path)
		#expect(lines == ["parent", "\tchild", "\tnew child", "sibling"])
	}

	@Test func `addNestedTodoDoubleIndentsNestedChild`() throws {
		try IO.write(["parent", "\tchild"], to: todo_path)
		try add_nested("grandchild", after: 2, fpath: todo_path)

		let lines = IO.read(todo_path)
		#expect(lines == ["parent", "\tchild", "\t\tgrandchild"])
	}

	@Test func `appendToDoneCreatesFileAndAppends`() {
		add_to_done("first task", fpath: done_path)
		add_to_done("second task", fpath: done_path)

		let lines = IO.read(done_path)
		#expect(lines.count == 2)
		#expect(lines.first?.hasSuffix("  first task") ?? false)
		#expect(lines.last?.hasSuffix("  second task") ?? false)
		#expect(lines.first?.prefix(14).allSatisfy({ $0.isNumber }) ?? false)
	}

	@Test func `removeLineThenAddTodoStartsAtLine1`() throws {
		try add("first", fpath: todo_path)
		_ = try remove(1, from: todo_path)
		try add("second", fpath: todo_path)

		let lines = IO.read(todo_path)
		#expect(lines == ["second"])
	}

	@Test func `finalizeTodoMovesToDoneAndRemovesFromTasks`() throws {
		try IO.write(["first", "second"], to: todo_path)
		try complete_todo(line: 1, launch_editor: false, todo_fpath: todo_path, done_fpath: done_path, repo: nil)

		let remaining = IO.read(todo_path)
		#expect(remaining == ["second"])

		let done = IO.read(done_path)
		#expect(done.first?.hasSuffix("  first") == true)
	}
}


@Suite struct TodoTests_2 {
	@Test func `list_skips_childs`() {
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

	@Test func `list_childs_shows_parent_childs`() {
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
@Suite class TodoTests_remove {

	lazy var tmp = FileManager.default.temporaryDirectory.appendingPathComponent("t-tests-rwc—\(UUID().uuidString)").path
	lazy var todo_path = tmp + "/.tasks.txt"
	lazy var done_path = tmp + "/.tasks.done"

	init() { try! FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true) }
	deinit { try? FileManager.default.removeItem(atPath: tmp) }

	// MARK: Unit – Todo.remove

	@Test func `remove removes parent and its direct children`() throws {
		let lines  = ["parent", "\tchild1", "\tchild2", "sibling"]
		let (result, removed) = try Todo.remove(1, from: lines)
		#expect(removed == "parent")
		#expect(result  == ["sibling"])
	}

	@Test func `remove removes parent and deeply nested descendants`() throws {
		let lines  = ["parent", "\tchild", "\t\tgrandchild", "sibling"]
		let (result, removed) = try Todo.remove(1, from: lines)
		#expect(removed == "parent")
		#expect(result  == ["sibling"])
	}

	@Test func `remove on a leaf removes only that line`() throws {
		let lines  = ["parent", "\tchild1", "\tchild2"]
		let (result, removed) = try Todo.remove(2, from: lines)
		#expect(removed == "child1")
		#expect(result  == ["parent", "\tchild2"])
	}

	@Test func `remove on a node without children behaves like plain remove`() throws {
		let lines = ["first", "second", "third"]
		let (result, removed) = try Todo.remove(2, from: lines)
		#expect(removed == "second")
		#expect(result  == ["first", "third"])
	}

	@Test func `remove with invalid line throws`() throws {
		let lines = ["only line"]
		#expect(throws: Todo.WrongLineNumber.self) {
			try Todo.remove(99, from: lines)
		}
	}

	// MARK: Integration – remove -r strips children from file

	@Test func `remove -r strips parent and all children from the tasks file`() throws {
		try IO.write(["parent", "\tchild1", "\tchild2", "sibling"], to: todo_path)
		let removed = try remove(1, from: todo_path)
		#expect(removed == "parent")
		#expect(IO.read(todo_path) == ["sibling"])
	}

	@Test func `remove -r on a node with no children removes only that node`() throws {
		try IO.write(["first", "second", "third"], to: todo_path)
		let removed = try remove(2, from: todo_path)
		#expect(removed == "second")
		#expect(IO.read(todo_path) == ["first", "third"])
	}

	// MARK: Integration – complete -f moves parent to done and removes children

	@Test func `complete -f moves parent to done and removes parent + children from tasks`() throws {
		try IO.write(["parent", "\tchild1", "\tchild2", "sibling"], to: todo_path)
		try complete_todo(line: 1, launch_editor: false, todo_fpath: todo_path, done_fpath: done_path, repo: nil)

		#expect(IO.read(todo_path) == ["sibling"])

		let done = IO.read(done_path)
		#expect(done.count == 1)
		#expect(done.first?.hasSuffix("  parent") == true)
	}

	@Test func `complete -f on a leaf moves it to done and leaves other tasks intact`() throws {
		try IO.write(["parent", "\tchild", "sibling"], to: todo_path)
		try complete_todo(line: 2, launch_editor: false, todo_fpath: todo_path, done_fpath: done_path, repo: nil)

		#expect(IO.read(todo_path) == ["parent", "sibling"])

		let done = IO.read(done_path)
		#expect(done.count == 1)
		#expect(done.first?.hasSuffix("  child") == true)
	}

	@Test func `complete -f with deeply nested children removes all descendants`() throws {
		try IO.write(["parent", "\tchild", "\t\tgrandchild", "sibling"], to: todo_path)
		try complete_todo(line: 1, launch_editor: false, todo_fpath: todo_path, done_fpath: done_path, repo: nil)

		#expect(IO.read(todo_path) == ["sibling"])

		let done = IO.read(done_path)
		#expect(done.count == 1)
		#expect(done.first?.hasSuffix("  parent") == true)
	}
}

