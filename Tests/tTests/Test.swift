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
    
    @Test func addTodoAppendsToFile() throws {
        try add("first", fpath: todo_path)
        try add("second", fpath: todo_path)
        
        let lines = IO.read(todo_path)
        #expect(lines == ["first", "second"])
    }
    
    @Test func todoParseSkipsEmptyLines() {
        let todos = Todo.parse(from: ["first", "", "third"])
        #expect(todos == [
            Todo.t(line: 1, text: "first", indent: 0),
            Todo.t(line: 3, text: "third", indent: 0)
        ])
    }
    
    @Test func removeLineRemovesCorrectLine() throws {
        try IO.write(["first", "second", "third"], to: todo_path)
        let removed = try remove(2, from: todo_path)
        #expect(removed == "second")
        
        let lines = IO.read(todo_path)
        #expect(lines == ["first", "third"])
    }
    
    @Test func addNestedTodoInsertsAfterChildren() throws {
        try IO.write(["parent", "\tchild", "sibling"], to: todo_path)
        try add_nested("new child", after: 1, fpath: todo_path)
        
        let lines = IO.read(todo_path)
        #expect(lines == ["parent", "\tchild", "\tnew child", "sibling"])
    }
    
    @Test func addNestedTodoDoubleIndentsNestedChild() throws {
        try IO.write(["parent", "\tchild"], to: todo_path)
        try add_nested("grandchild", after: 2, fpath: todo_path)
        
        let lines = IO.read(todo_path)
        #expect(lines == ["parent", "\tchild", "\t\tgrandchild"])
    }
    
    @Test func appendToDoneCreatesFileAndAppends() {
        add_to_done("first task", fpath: done_path)
        add_to_done("second task", fpath: done_path)
        
        let lines = IO.read(done_path)
        #expect(lines.count == 2)
        #expect(lines.first?.hasSuffix("  first task") ?? false)
        #expect(lines.last?.hasSuffix("  second task") ?? false)
        #expect(lines.first?.prefix(14).allSatisfy({ $0.isNumber }) ?? false)
    }
    
    @Test func removeLineThenAddTodoStartsAtLine1() throws {
        try add("first", fpath: todo_path)
        _ = try remove(1, from: todo_path)
        try add("second", fpath: todo_path)
        
        let lines = IO.read(todo_path)
        #expect(lines == ["second"])
    }
    
    @Test func finalizeTodoMovesToDoneAndRemovesFromTasks() throws {
        try IO.write(["first", "second"], to: todo_path)
        try complete_todo(line: 1, launch_editor: false, todo_fpath: todo_path, done_fpath: done_path, repo: nil)
        
        let remaining = IO.read(todo_path)
        #expect(remaining == ["second"])
        
        let done = IO.read(done_path)
        #expect(done.first?.hasSuffix("  first") == true)
    }
}
