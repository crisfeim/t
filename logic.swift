
typealias TodoPath = String
typealias DonePath = String

// MARK: - Effects
enum Effects {
    typealias All = (
        io: IO,
        vcs: VCS,
        put: (String) -> Void,
        currentDirectory: () -> String,
        now: () -> Date,
        editor: (String) throws(T.Error) -> Void,
        copyToClipboard: (String) -> Void
    )
    
    typealias IO = (
        read: (String) throws(T.Error) -> [String],
        write: ([String], String) throws(T.Error) -> Void,
        delete: (String) throws(T.Error) -> Void,
        all: () throws(T.Error) -> [String],
    )
    
    typealias VCS = (
        get: (String) -> (dir: String, type: String)?,
        commit: (String, String, String) throws(T.Error) -> Void
    )
}

// MARK: - Logic

let runList: (TodoPath, Effects.All) throws(T.Error) -> Void = { todoPath, fx  in
    try fx.io.read(todoPath).enumerated()
    .map { idx, content in (idx + 1).description + " " + content }
    .forEach(fx.put)
}

let runAdd: (TodoPath, String, Effects.All) throws(T.Error) -> Void = { todoPath, todo, fx in
    let todos = try fx.io.read(todoPath)
    let updated = todos + [todo]
    try fx.io.write(updated, todoPath)
    fx.put(updated.count.description + " " + todo)
}

let runRemove: (TodoPath, [Int], Effects.All) throws(T.Error) -> Void = { todoPath, lines, fx throws(T.Error) in
    let todos = try fx.io.read(todoPath).enumerated()
    let shouldRemove = !lines.map { todos.map { offset, _ in offset + 1 }.contains($0) }.contains(false)
    guard shouldRemove else { throw .wrongLines(lines) }
    let rest = todos.filter { offset, _ in !lines.contains(offset + 1) }.map(\.element)
    try fx.io.write(rest, todoPath)
    fx.put("Todo removed")
}

let runComplete: (TodoPath, DonePath, Int, Effects.All) throws(T.Error) -> Void = { todoPath, donePath, line, fx throws(T.Error) in
    let todos = try fx.io.read(todoPath)
    guard let (removed, rest) = todos.removing(at: line - 1) else { throw .wrongLines([line]) }
    let done = (try? fx.io.read(donePath)) ?? []
    try fx.io.write(done + [yyyyMMddHHmmss.string(from: fx.now())  + " " + removed], donePath)
    try fx.io.write(rest, todoPath)
    fx.put("Todo completed")
}

let runEdit: (TodoPath, Int, Effects.All) throws(T.Error) -> Void = { todoPath, line, fx throws(T.Error) in
    let todos = try fx.io.read(todoPath)
    let idx = line - 1
    guard todos.indices.contains(idx) else { throw .wrongLines([line]) }
    let original = todos[idx]
    
    let updated = try withTempFile(prefix: "todo_edit", content: [original], fx: fx) { tmpPath throws(T.Error) in
        try fx.editor(tmpPath)
        let lines = try fx.io.read(tmpPath)
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }
    
    guard !updated.isEmpty, updated != original else { return fx.put("No changes") }
    try fx.io.write(todos * { $0[idx] = updated }, todoPath)
    fx.put("Todo updated: \(updated)")
}


let runAll: (Effects.All) throws(T.Error) -> Void = { fx throws(T.Error) in
    try fx.io.all().enumerated().forEach { idx, path in
        fx.put("\(idx + 1) \(path)")
    }
}

let runCommit: (Int, TodoPath, DonePath, Bool, Effects.All) throws(T.Error) -> Void = { id, todoPath, donePath, editMsg, fx throws(T.Error) in
    
    guard let repo = fx.vcs.get(fx.currentDirectory()) else { throw .vcs("Not a repository") }
    let todos = try fx.io.read(todoPath)
    guard let (removedTodo, rest) = todos.removing(at: id - 1) else { throw .wrongLines([id]) }
    
    let finalMessage = if editMsg {
        try withTempFile(prefix: "t_commit", content: [removedTodo], fx: fx) { tmpPath throws(T.Error) in
            try fx.editor(tmpPath)
            let lines = try fx.io.read(tmpPath)
            let msg = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !msg.isEmpty else { throw T.Error.vcs("Commit aborted due to empty message") }
            return msg
        }
    } else {
        removedTodo
    }
    
    try fx.vcs.commit(finalMessage, repo.type, repo.dir)
    let done = (try? fx.io.read(donePath)) ?? []
    try fx.io.write(done + [yyyyMMddHHmmss.string(from: fx.now())  + " " + removedTodo], donePath)
    try fx.io.write(rest, todoPath)
    fx.put("Todo completed and committed successfully via \(repo.type)")
}


let runProjectsList: (Effects.All) throws(T.Error) -> Void = { fx in
    let todoFiles = try fx.io.all()
    let sortedFiles = todoFiles |> sortMatches
    
    for path in sortedFiles {
        fx.put(path)
        
        let lines = try fx.io.read(path)
        guard !lines.isEmpty else { continue }
        
        for (index, line) in lines.enumerated() {
            fx.put("    \(index + 1) \(line)")
        }
    }
}

let runCopy: (TodoPath, Int, Effects.All) throws(T.Error) -> Void = { todoPath, line, fx throws(T.Error) in 
    let todos = try fx.io.read(todoPath)
    let idx = line - 1
    guard todos.indices.contains(line - 1) else { throw .wrongLines([line]) }
    
    let todoToCopy = todos[idx]
    
    fx.copyToClipboard(todoToCopy)
    fx.put("Copied to clipboard: \(todoToCopy)")
}


// MARK: - Error
enum T {
    typealias CLI = ([String]) throws(T.Error) -> Void
    
    enum Error: Swift.Error {
        case wrongLines([Int])
        case conflictingFlags
        case unhandledFlag
        case fileSystem(FileSystem)
        case editor(FileSystem)
        case notFound(_ projectName: String, available: [String])
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
    static let fs  =       { T.Error.fileSystem(ErrorMapper.map($0)) }
    static let fsUnknown = { (e: Error) in T.Error.fileSystem(.unknownIO(e.localizedDescription)) }
    static let vcs =       { (e: Error) in T.Error.vcs(e.localizedDescription) }
    static let editor =    { T.Error.editor(ErrorMapper.map($0)) } 
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
            case let .wrongLines(lines):
            return "lines \(lines.map(\.description).joined(separator: ", ")) does not exist"
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
            case let .notFound(wrongProject, available):
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

func withTempFile<R>(prefix: String, content: [String], fx: Effects.All, block: (String) throws(T.Error) -> R) throws(T.Error) -> R {
    let tmpPath = NSTemporaryDirectory() + "\(prefix)_\(UUID().uuidString).txt"
    defer { try? fx.io.delete(tmpPath) }
    try fx.io.write(content, tmpPath)
    return try block(tmpPath)
}


// Filter to show more relevant folder 
// (ej. "t project cristian"  --> /Users/cristian before that /Users/cristian/💻/t)
let sortMatches: ([String]) -> [String] = { todoFiles in 
    todoFiles.sorted { path1, path2 in
        let count1 = path1.components(separatedBy: "/").count
        let count2 = path2.components(separatedBy: "/").count
        if count1 != count2 {
            return count1 < count2
        }
        if path1.count != path2.count { return path1.count < path2.count }
        return path1 < path2
    }
}