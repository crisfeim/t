import Testing
import Foundation
@testable import t

@Suite struct TodoTests {
    
    @Test func addTodoAppendsToFile() {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("t-tests").path
        
        try? fm.removeItem(atPath: tmpDir)
        try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }
        
        let path = tmpDir + "/tasks"
        addTodo("first", taskPath: path)
        addTodo("second", taskPath: path)
        
        let lines = IO.read(path)
        #expect(lines.count == 2)
        #expect(lines[0] == "first")
        #expect(lines[1] == "second")
    }
    
    @Test func todoParseSkipsEmptyLines() {
        let todos = Todo.parse(from: ["first", "", "third"])
        #expect(todos.count == 2)
        #expect(todos[0].line_number == 1)
        #expect(todos[0].text == "first")
        #expect(todos[1].line_number == 3)
        #expect(todos[1].text == "third")
    }
    
    @Test func removeLineRemovesCorrectLine() {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("t-tests").path
        
        try? fm.removeItem(atPath: tmpDir)
        try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }
        
        let path = tmpDir + "/tasks"
        IO.write(["first", "second", "third"], to: path)
        let removed = removeLine(2, from: path)
        #expect(removed == "second")
        
        let lines = IO.read(path)
        #expect(lines.count == 2)
        #expect(lines[0] == "first")
        #expect(lines[1] == "third")
    }
    
    @Test func addNestedTodoInsertsAfterChildren() {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("t-tests").path
        
        try? fm.removeItem(atPath: tmpDir)
        try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }
        
        let path = tmpDir + "/tasks"
        IO.write(["parent", "\tchild", "sibling"], to: path)
        addNestedTodo("new child", after: 1, taskPath: path)
        
        let lines = IO.read(path)
        #expect(lines.count == 4)
        #expect(lines[0] == "parent")
        #expect(lines[1] == "\tchild")
        #expect(lines[2] == "\tnew child")
        #expect(lines[3] == "sibling")
    }
    
    @Test func addNestedTodoDoubleIndentsNestedChild() {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("t-tests").path
        
        try? fm.removeItem(atPath: tmpDir)
        try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }
        
        let path = tmpDir + "/tasks"
        IO.write(["parent", "\tchild"], to: path)
        addNestedTodo("grandchild", after: 2, taskPath: path)
        
        let lines = IO.read(path)
        #expect(lines.count == 3)
        #expect(lines[2] == "\t\tgrandchild")
    }
    
    @Test func appendToDoneCreatesFileAndAppends() {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("t-tests").path
        
        try? fm.removeItem(atPath: tmpDir)
        try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }
        
        let path = tmpDir + "/.tasks.done"
        appendToDone("first task", donePath: path)
        appendToDone("second task", donePath: path)
        
        let lines = IO.read(path)
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix("  first task"))
        #expect(lines[1].hasSuffix("  second task"))
        #expect(lines[0].prefix(14).allSatisfy({ $0.isNumber }))
    }
    
    @Test func removeLineThenAddTodoStartsAtLine1() {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("t-empty-line-test").path
        
        try? fm.removeItem(atPath: tmpDir)
        try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }
        
        let path = tmpDir + "/tasks"
        addTodo("first", taskPath: path)
        _ = removeLine(1, from: path)
        addTodo("second", taskPath: path)
        
        let lines = IO.read(path)
        #expect(lines.count == 1)
        #expect(lines[0] == "second")
    }
    
    @Test func finalizeTodoMovesToDoneAndRemovesFromTasks() {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("t-tests").path
        
        try? fm.removeItem(atPath: tmpDir)
        try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }
        
        let taskPath = tmpDir + "/tasks"
        let donePath = tmpDir + "/.tasks.done"
        IO.write(["first", "second"], to: taskPath)
        finalizeTodo(lineNumber: 1, editMessage: false, taskPath: taskPath, donePath: donePath, repo: nil)
        
        let remaining = IO.read(taskPath)
        #expect(remaining.count == 1)
        #expect(remaining[0] == "second")
        
        let done = IO.read(donePath)
        #expect(done.count == 1)
        #expect(done[0].hasSuffix("  first"))
    }
    
    @Test func vcsRootDetectsFossil() {
        let fm = FileManager.default
        let repoDir = fm.temporaryDirectory.appendingPathComponent("t-vcs-detection").path
        
        try? fm.removeItem(atPath: repoDir)
        try! fm.createDirectory(atPath: repoDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repoDir) }
        
        _ = Runner.run("fossil init repo.fossil", inDirectory: repoDir)
        _ = Runner.run("fossil open repo.fossil", inDirectory: repoDir)
        
        let result = VCS.root(from: repoDir)
        #expect(result?.root == repoDir)
        #expect(result?.vcs == "fossil")
    }
    
    @Test func fossilIntegration() {
        let fm = FileManager.default
        let repoDir = fm.temporaryDirectory.appendingPathComponent("t-fossil-tests").path
        
        try? fm.removeItem(atPath: repoDir)
        try! fm.createDirectory(atPath: repoDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repoDir) }
        
        _ = Runner.run("fossil init repo.fossil", inDirectory: repoDir)
        _ = Runner.run("fossil open repo.fossil", inDirectory: repoDir)
        
        let taskPath = repoDir + "/tasks"
        let donePath = repoDir + "/.tasks.done"
        IO.write(["fix bug", "write docs"], to: taskPath)
        
        finalizeTodo(lineNumber: 1, editMessage: false, taskPath: taskPath, donePath: donePath, repo: (repoDir, "fossil"))
        
        let remaining = IO.read(taskPath)
        #expect(remaining.count == 1)
        #expect(remaining[0] == "write docs")
        
        let done = IO.read(donePath)
        #expect(done.count == 1)
        #expect(done[0].hasSuffix("  fix bug"))
    }
}
