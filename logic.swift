// MARK: - Logic
typealias TodoPath = String
typealias DonePath = String

let runList: (TodoPath, Effects) throws(AppError) -> Void = { todoPath, fx  in
    try fx.fs.read(todoPath).enumerated()
    .map { idx, content in (idx + 1).description + " " + content }
    .forEach(fx.put)
}

let runAdd: (TodoPath, String, Effects) throws(AppError) -> Void = { todoPath, todo, fx in
    let todos = try fx.fs.read(todoPath)
    let updated = todos + [todo]
    try fx.fs.write(updated, todoPath)
    fx.put(updated.count.description + " " + todo)
}

let runRemove: (TodoPath, [Int], Effects) throws(AppError) -> Void = { todoPath, lines, fx throws(AppError) in
    let todos = try fx.fs.read(todoPath)
    let rest = todos.enumerated().filter { offset, _ in !lines.contains(offset + 1) }.map(\.element)
    try fx.fs.write(rest, todoPath)
    fx.put("Task removed")
}

let runComplete: (TodoPath, DonePath, Int, Effects) throws(AppError) -> Void = { todoPath, donePath, line, fx throws(AppError) in
    let todos = try fx.fs.read(todoPath)
    guard let (removed, rest) = todos.removing(at: line - 1) else { throw AppError.wrongLine(line) }
    let done = (try? fx.fs.read(donePath)) ?? []
    try fx.fs.write(done + [fx.date + " " + removed], donePath)
    try fx.fs.write(rest, todoPath)
    fx.put("Task completed")
}

let runEdit: (TodoPath, Int, Effects) throws(AppError) -> Void = { todoPath, line, fx throws(AppError) in
    let todos = try fx.fs.read(todoPath)
    let idx = line - 1
    guard todos.indices.contains(idx) else { throw AppError.wrongLine(line) }
    
    let tmpPath = NSTemporaryDirectory() + "todo_edit_\(UUID().uuidString).txt"
    defer { try? fx.fs.delete(tmpPath) }
    let original = todos[idx]
    
    try fx.fs.write([original], tmpPath)
    try fx.editor(tmpPath)
    
    let lines = try fx.fs.read(tmpPath)
    let updated = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    
    guard !updated.isEmpty, updated != original else { return fx.put("No changes") }
    try fx.fs.write(todos * { $0[idx] = updated }, todoPath)
    fx.put("Task updated: \(updated)")
}

let runAll: (Effects) throws(AppError) -> Void = { fx throws(AppError) in
    try fx.fs.all().enumerated().forEach { idx, path in
        fx.put("\(idx + 1) \(path)")
    }
}

let runListByProject: (String, Effects) throws(AppError) -> Void = { projectName, fx throws(AppError) in
    let todoFiles = try fx.fs.all()
    
    guard let first = todoFiles.first(where: { $0.contains(projectName) }) else {
        throw AppError.unexistentProject(wrongProject: projectName, available: todoFiles)
    }
    
    try runList(first, fx)
}

let runCommit: (Int, TodoPath, DonePath, Bool, Effects) throws(AppError) -> Void = { id, todoPath, donePath, launchingEditor, fx throws(AppError) in
    guard let repo = fx.vcs.get(fx.currentDirectory()) else { throw AppError.vcs("Not a repository") }
    
    let todos = try fx.fs.read(todoPath)
    guard let (removedTask, rest) = todos.removing(at: id - 1) else { throw AppError.wrongLine(id) }
    
    let finalMessage: String
    
    if launchingEditor {
        let tmpPath = NSTemporaryDirectory() + "t_commit_\(UUID().uuidString).txt"
        try fx.fs.write([removedTask], tmpPath)
        defer { try? fx.fs.delete(tmpPath) }
        
        try fx.editor(tmpPath)
        
        let lines = try fx.fs.read(tmpPath)
        let msg = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { throw AppError.vcs("Commit aborted due to empty message") }
        finalMessage = msg
    } else {
        finalMessage = removedTask
    }
    
    try fx.vcs.commit(finalMessage, repo.type, repo.dir)
    let done = (try? fx.fs.read(donePath)) ?? []
    try fx.fs.write(done + [fx.date + " " + removedTask], donePath)
    try fx.fs.write(rest, todoPath)
    
    fx.put("Task completed and committed successfully via \(repo.type)")
}

// MARK: - Effects
struct Effects {
    typealias Path = String
    
    let fs: FileSystem
    let vcs: VersionControl
    let put: (String) -> Void
    let currentDirectory: () -> String
    var now: () -> Date
    var editor: (Path) throws(AppError) -> Void
    var date: String { yyyyMMddHHmmss.string(from: now()) }
    
    struct FileSystem {
        let read: (Path) throws(AppError) -> [String]
        let write: ([String], Path) throws(AppError) -> Void
        let delete: (Path) throws(AppError) -> Void
        let all: () throws(AppError) -> [Path]
    }
    
    struct VersionControl {
        typealias System = String
        let get: (Path) -> (dir: String, type: System)?
        let commit: (String, System, Path) throws(AppError) -> Void
    }
}

let yyyyMMddHHmmss: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMddHHmmss"
    return formatter
}()



// MARK: - Error
enum AppError: Error {
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

// MARK: - Error Mapper
import Foundation

enum ErrorMapper {
    static func map(_ error: Error) -> AppError.FileSystem {
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

extension AppError {
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
            return "Commit error \(description)"
             
        }
    }
}

// MARK: - Helpers
extension Array {
    func removing(at idx: Int) -> (removed: Element, rest: [Element])? {
        guard indices.contains(idx) else { return nil }
        return (self[idx], enumerated().filter { $0.offset != idx }.map(\.element))
    }
}

infix operator *: MultiplicationPrecedence
func *<A>(lhs: A, rhs: (inout A) -> Void) -> A {
    var copy = lhs
    rhs(&copy)
    return copy
}