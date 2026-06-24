
typealias TodoPath = String
typealias DonePath = String

// MARK: - Effects
struct Effects {
    typealias Path = String
    
    let fs: FileSystem
    var vcs: VersionControl
    let put: (String) -> Void
    let currentDirectory: () -> String
    var now: () -> Date
    var editor: (Path) throws(T.Error) -> Void
    var date: String { yyyyMMddHHmmss.string(from: now()) }
    
    struct FileSystem {
        let read: (Path) throws(T.Error) -> [String]
        let write: ([String], Path) throws(T.Error) -> Void
        let delete: (Path) throws(T.Error) -> Void
        let all: () throws(T.Error) -> [Path]
    }
    
    struct VersionControl {
        typealias System = String
        var get: (Path) -> (dir: String, type: System)?
        var commit: (String, System, Path) throws(T.Error) -> Void
    }
}

// MARK: - Logic

let runList: (TodoPath, Effects) throws(T.Error) -> Void = { todoPath, fx  in
    try fx.fs.read(todoPath).enumerated()
    .map { idx, content in (idx + 1).description + " " + content }
    .forEach(fx.put)
}

let runAdd: (TodoPath, String, Effects) throws(T.Error) -> Void = { todoPath, todo, fx in
    let todos = try fx.fs.read(todoPath)
    let updated = todos + [todo]
    try fx.fs.write(updated, todoPath)
    fx.put(updated.count.description + " " + todo)
}

let runRemove: (TodoPath, [Int], Effects) throws(T.Error) -> Void = { todoPath, lines, fx throws(T.Error) in
    let todos = try fx.fs.read(todoPath)
    let rest = todos.enumerated().filter { offset, _ in !lines.contains(offset + 1) }.map(\.element)
    try fx.fs.write(rest, todoPath)
    fx.put("Todo removed")
}

let runComplete: (TodoPath, DonePath, Int, Effects) throws(T.Error) -> Void = { todoPath, donePath, line, fx throws(T.Error) in
    let todos = try fx.fs.read(todoPath)
    guard let (removed, rest) = todos.removing(at: line - 1) else { throw .wrongLine(line) }
    let done = (try? fx.fs.read(donePath)) ?? []
    try fx.fs.write(done + [fx.date + " " + removed], donePath)
    try fx.fs.write(rest, todoPath)
    fx.put("Todo completed")
}

let runEdit: (TodoPath, Int, Effects) throws(T.Error) -> Void = { todoPath, line, fx throws(T.Error) in
    let todos = try fx.fs.read(todoPath)
    let idx = line - 1
    guard todos.indices.contains(idx) else { throw .wrongLine(line) }
    let original = todos[idx]
    
    let updated = try withTempFile(prefix: "todo_edit", content: [original], fx: fx) { tmpPath throws(T.Error) in
        try fx.editor(tmpPath)
        let lines = try fx.fs.read(tmpPath)
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }
    
    guard !updated.isEmpty, updated != original else { return fx.put("No changes") }
    try fx.fs.write(todos * { $0[idx] = updated }, todoPath)
    fx.put("Todo updated: \(updated)")
}


let runAll: (Effects) throws(T.Error) -> Void = { fx throws(T.Error) in
    try fx.fs.all().enumerated().forEach { idx, path in
        fx.put("\(idx + 1) \(path)")
    }
}

let runListByProject: (String, Effects) throws(T.Error) -> Void = { projectName, fx throws(T.Error) in
    let todoFiles = try fx.fs.all()
    
    guard let first = todoFiles.first(where: { $0.contains(projectName) }) else {
        throw .unexistentProject(wrongProject: projectName, available: todoFiles)
    }
    
    try runList(first, fx)
}

let runCommit: (Int, TodoPath, DonePath, Bool, Effects) throws(T.Error) -> Void = { id, todoPath, donePath, editMsg, fx throws(T.Error) in
    
    guard let repo = fx.vcs.get(fx.currentDirectory()) else { throw .vcs("Not a repository") }
    let todos = try fx.fs.read(todoPath)
    guard let (removedTodo, rest) = todos.removing(at: id - 1) else { throw .wrongLine(id) }
    
    let finalMessage = if editMsg {
        try withTempFile(prefix: "t_commit", content: [removedTodo], fx: fx) { tmpPath throws(T.Error) in
            try fx.editor(tmpPath)
            let lines = try fx.fs.read(tmpPath)
            let msg = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !msg.isEmpty else { throw T.Error.vcs("Commit aborted due to empty message") }
            return msg
        }
    } else {
        removedTodo
    }
    
    try fx.vcs.commit(finalMessage, repo.type, repo.dir)
    let done = (try? fx.fs.read(donePath)) ?? []
    try fx.fs.write(done + [fx.date + " " + removedTodo], donePath)
    try fx.fs.write(rest, todoPath)
    fx.put("Todo completed and committed successfully via \(repo.type)")
}

// MARK: - Error
enum T {
    typealias CLI = ([String]) throws(T.Error) -> Void
    
    enum Error: Swift.Error {
        case wrongLine(Int)
        case conflictingFlags
        case unhandledFlag
        case fileSystem(FileSystem)
        case editor(FileSystem)
        case unexistentProject(wrongProject: String, available: [String])
        case vcs(String)
        
        enum FileSystem {
            case notFound
            case permissionDenied
            case diskFull    
            case unknownIO(String)
        }
    }
}

extension T.Error {
    static let fs  = { T.Error.fileSystem(ErrorMapper.map($0)) }
    static let fsUnknown = { (e: Error) in T.Error.fileSystem(.unknownIO(e.localizedDescription)) }
    static let vcs = { (e: Error) in T.Error.vcs(e.localizedDescription) }
}

extension T.Error:            Equatable {}
extension T.Error.FileSystem: Equatable {}

// MARK: - Error Mapper
import Foundation

enum ErrorMapper {
    static func map(_ error: Error) -> T.Error.FileSystem {
        let nsError = error as NSError
        
        switch (nsError.domain, nsError.code) {
            case (NSCocoaErrorDomain, NSFileReadNoSuchFileError), 
            (NSCocoaErrorDomain, NSFileNoSuchFileError),
            (NSPOSIXErrorDomain, Int(ENOENT)):
            return .notFound
            
            case (NSCocoaErrorDomain, NSFileWriteNoPermissionError), 
            (NSCocoaErrorDomain, NSFileReadNoPermissionError),
            (NSPOSIXErrorDomain, Int(EACCES)), 
            (NSPOSIXErrorDomain, Int(EPERM)):
            return .permissionDenied
            
            case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError), 
            (NSPOSIXErrorDomain, Int(ENOSPC)):
            return .diskFull
            
            default:
            return .unknownIO(nsError.localizedDescription)
        }
    }
}

extension T.Error {
    var message: String {
        switch self {
            case let .wrongLine(line):
            return "line \(line) does not exist"
            case .conflictingFlags:
            return "invalid arguments"
            case .unhandledFlag:
            return "unknown command"
            case .fileSystem(.notFound):
            return "file not found"
            case .fileSystem(.permissionDenied):
            return "permission denied"
            case .fileSystem(.diskFull), .editor(.diskFull):
            return "disk full"
            case let .fileSystem(.unknownIO(description)):
            return "\(description)"
            case .editor(.notFound):
            return "editor not found"
            case .editor(.permissionDenied):
            return "editor permission denied"
            case let .editor(.unknownIO(description)):
            return "editor failed: \(description)"
            case let .unexistentProject(wrongProject, available):
            return "Project doesn't exist: \(wrongProject), available locations: \(available.reduce("") { acc, next in acc + "\n  " + next })"
            case let .vcs(description): 
            return "Commit error: \(description)"
             
        }
    }
}

// MARK: - Helpers

let yyyyMMddHHmmss: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMddHHmmss"
    return formatter
}()


extension Array {
    func removing(at idx: Int) -> (removed: Element, rest: [Element])? {
        guard indices.contains(idx) else { return nil }
        return (self[idx], enumerated().filter { $0.offset != idx }.map(\.element))
    }
}

// Asterisk
infix operator *: MultiplicationPrecedence
func *<A>(lhs: A, rhs: (inout A) -> Void) -> A {
    var copy = lhs
    rhs(&copy)
    return copy
}

// Pipe forward
infix operator |>: MultiplicationPrecedence
func |><A, B>(lhs: A, rhs: (A) -> B) -> B {
    rhs(lhs)
}

func withTempFile<R>(prefix: String, content: [String], fx: Effects, block: (String) throws(T.Error) -> R) throws(T.Error) -> R {
    let tmpPath = NSTemporaryDirectory() + "\(prefix)_\(UUID().uuidString).txt"
    defer { try? fx.fs.delete(tmpPath) }
    try fx.fs.write(content, tmpPath)
    return try block(tmpPath)
}