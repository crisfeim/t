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
        try addTodo("first", taskPath: todo_path)
        try addTodo("second", taskPath: todo_path)
        
        let lines = IO.read(todo_path)
        #expect(lines == ["first", "second"])
    }
    
    @Test func todoParseSkipsEmptyLines() {
        let todos = Todo.parse(from: ["first", "", "third"])
        #expect(todos == [
            Todo.t(line_number: 1, text: "first", indent: 0),
            Todo.t(line_number: 3, text: "third", indent: 0)
        ])
    }
    
    @Test func removeLineRemovesCorrectLine() throws {
        try IO.write(["first", "second", "third"], to: todo_path)
        let removed = try removeLine(2, from: todo_path)
        #expect(removed == "second")
        
        let lines = IO.read(todo_path)
        #expect(lines == ["first", "third"])
    }
    
    @Test func addNestedTodoInsertsAfterChildren() throws {
        try IO.write(["parent", "\tchild", "sibling"], to: todo_path)
        try addNestedTodo("new child", after: 1, taskPath: todo_path)
        
        let lines = IO.read(todo_path)
        #expect(lines == ["parent", "\tchild", "\tnew child", "sibling"])
    }
    
    @Test func addNestedTodoDoubleIndentsNestedChild() throws {
        try IO.write(["parent", "\tchild"], to: todo_path)
        try addNestedTodo("grandchild", after: 2, taskPath: todo_path)
        
        let lines = IO.read(todo_path)
        #expect(lines == ["parent", "\tchild", "\t\tgrandchild"])
    }
    
    @Test func appendToDoneCreatesFileAndAppends() {
        appendToDone("first task", donePath: done_path)
        appendToDone("second task", donePath: done_path)
        
        let lines = IO.read(done_path)
        #expect(lines.count == 2)
        #expect(lines.first?.hasSuffix("  first task") ?? false)
        #expect(lines.last?.hasSuffix("  second task") ?? false)
        #expect(lines.first?.prefix(14).allSatisfy({ $0.isNumber }) ?? false)
    }
    
    @Test func removeLineThenAddTodoStartsAtLine1() throws {
        try addTodo("first", taskPath: todo_path)
        _ = try removeLine(1, from: todo_path)
        try addTodo("second", taskPath: todo_path)
        
        let lines = IO.read(todo_path)
        #expect(lines == ["second"])
    }
    
    @Test func finalizeTodoMovesToDoneAndRemovesFromTasks() throws {
        try IO.write(["first", "second"], to: todo_path)
        try finalizeTodo(lineNumber: 1, editMessage: false, taskPath: todo_path, donePath: done_path, repo: nil)
        
        let remaining = IO.read(todo_path)
        #expect(remaining == ["second"])
        
        let done = IO.read(done_path)
        #expect(done.first?.hasSuffix("  first") == true)
    }
}
