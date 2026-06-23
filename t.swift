import Foundation

// ==========================================
// 1. MODELO DE DATOS Y ERRORES
// ==========================================
enum Command {
    case list
    case add(String)
    case remove(Int)
    case complete(Int)
    case edit(Int)
}

typealias Args = [String]
typealias Path = String
typealias TodoPath = Path
typealias DonePath = Path

enum AppError: Error {
    case wrongLine(Int)
    case conflictingFlags
    case unhandledFlag
    case fileSystem(FileSystemError)
    case editor(FileSystemError)
    
    enum FileSystemError {
        case notFound
        case permissionDenied
        case diskFull    
        case unknownIO(String)
    }
}

enum ErrorMapper {
    static func map(_ error: Error) -> AppError.FileSystemError {
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
        }
    }
}

// ==========================================
// 2. ESTRUCTURA DEL Effects (INYECCIÓN)
// ==========================================

struct Effects {
    let fs: FileSystem
    let put: (String) -> Void
    var now: () -> Date
    var editor: (Path) throws(AppError) -> Void
    var date: String { yyyyMMddHHmmss.string(from: now()) }
    
    struct FileSystem {
        let read: (Path) throws(AppError) -> [String]
        let write: ([String], Path) throws(AppError) -> Void
        let delete: (Path) throws(AppError) -> Void
    }
}

let yyyyMMddHHmmss: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMddHHmmss"
    return formatter
}()

// ==========================================
// 3. LÓGICA DE NEGOCIO (GENÉRICA Y PURA)
// ==========================================
typealias t_cli = (Args) throws(AppError) -> Void

let make: (TodoPath, DonePath, Effects) -> t_cli = { todoPath, donePath, fx in
    return { args throws(AppError) in 
        switch try parseArgs(args) {
            case .list:
            try runList(todoPath, fx)
            case let .add(todo):
            try runAdd(todoPath, todo, fx)
            case let .remove(line):
            try runRemove(todoPath, line, fx)
            case let .complete(line):
            try runComplete(todoPath, donePath, line, fx)
            case let .edit(line):
            try runEdit(todoPath, line, fx)
        }
    }
}

let runList: (TodoPath, Effects) throws(AppError) -> Void = { path, fx  in
    try fx.fs.read(path).enumerated()
    .map { idx, content in (idx + 1).description + " " + content }
    .forEach(fx.put)
}

let runAdd: (TodoPath, String, Effects) throws(AppError) -> Void = { path, todo, fx in
    let todos = try fx.fs.read(path)
    let updated = todos + [todo]
    try fx.fs.write(updated, path)
    fx.put(updated.count.description + " " + todo)
}

let runRemove: (TodoPath, Int, Effects) throws(AppError) -> Void = { path, line, fx throws(AppError) in
    let todos = try fx.fs.read(path)
    guard let (_, rest) = todos.removing(at: line - 1) else { throw AppError.wrongLine(line) }
    try fx.fs.write(rest, path)
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

let runEdit: (TodoPath, Int, Effects) throws(AppError) -> Void = { path, line, fx throws(AppError) in
    let todos = try fx.fs.read(path)
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
    try fx.fs.write(todos * { $0[idx] = updated }, path)
    fx.put("Task updated: \(updated)")
}

// ==========================================
// 4. EXTENSIONES Y PARSER AUXILIARES
// ==========================================
extension Array {
    func removing(at idx: Int) -> (removed: Element, rest: [Element])? {
        guard indices.contains(idx) else { return nil }
        return (self[idx], enumerated().filter { $0.offset != idx }.map(\.element))
    }
}

let parseArgs: (Args) throws(AppError) -> Command = { args throws(AppError) in
    guard let first = args.first else { return .list }
    
    switch first {
        case "list":
        guard args.count == 1 else { throw AppError.conflictingFlags }
        return .list
        
        case "add":
        guard args.count == 2 else { throw AppError.conflictingFlags }
        return .add(args[1])
        
        case "remove":
        guard args.count == 2, let line = Int(args[1])
        else { throw AppError.conflictingFlags }
        return .remove(line)
        
        case "complete":
        guard args.count == 2, let line = Int(args[1])
        else { throw AppError.conflictingFlags }
        return .complete(line)
        
        case "edit":
        guard args.count == 2, let line = Int(args[1])
            else { throw AppError.conflictingFlags }
            return .edit(line)
        
        default:
        throw AppError.unhandledFlag
    }
}
// ==========================================
// 5. PRODUCCIÓN: IMPLEMENTACIÓN REAL
// ==========================================
extension Effects: @unchecked Sendable {
    static let live = Effects(
        fs: .init(
            read: { path throws(AppError) in
                do {
                    let content = try String(contentsOfFile: path, encoding: .utf8)
                    let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                    return lines.last == "" ? lines.dropLast().map { $0 } : lines
                } catch {
                    throw AppError.fileSystem(ErrorMapper.map(error))
                }
            },
            write: { lines, path throws(AppError) in
                let content = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
                do {
                    try content.write(toFile: path, atomically: true, encoding: .utf8)
                } catch {
                    throw AppError.fileSystem(ErrorMapper.map(error))
                }
            },
            delete: { path throws(AppError) in
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    throw AppError.fileSystem(ErrorMapper.map(error))
                }
            }
        ),
        put: { text in print(text) },
        now: { Date() },
        editor: { tmpPath throws(AppError) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/vi")
            process.arguments = [tmpPath]
            
            do {
                try process.run()
            } catch {
                throw AppError.editor(ErrorMapper.map(error))
            }
            
            // Put vi in the foreground so it can interact with the terminal
            tcsetpgrp(STDIN_FILENO, process.processIdentifier)
            // Wait until vi is done
            process.waitUntilExit()
            
            // Prevent the system from suspending us when taking back the terminal
            signal(SIGTTOU, SIG_IGN)
            // Take back the terminal to our program
            tcsetpgrp(STDIN_FILENO, getpgrp())
            // Restore default SIGTTOU behaviour
            signal(SIGTTOU, SIG_DFL)
        }
    )
}


// Helpers
infix operator *: MultiplicationPrecedence
func *<A>(lhs: A, rhs: (inout A) -> Void) -> A {
    var copy = lhs
    rhs(&copy)
    return copy
}

#if DEBUG
// ==========================================
// 6. TESTS: Tests de integración
// ==========================================
typealias SUT = (
    execute: (Args) throws(AppError) -> Void,
    todo: TodoPath,
    done: DonePath,
    tearDown: () -> Void
)

let makeSUT: (@escaping () -> Date, @escaping (String) throws(AppError) -> Void) -> SUT = { now, editor in
    let tempDir = NSTemporaryDirectory()
    let uuid = UUID().uuidString
    let todo = tempDir + "todo_\(uuid).txt"
    let done = tempDir + "done_\(uuid).txt"
    
    try? "".write(toFile: todo, atomically: true, encoding: .utf8)
    
    let tearDown = {
        try? FileManager.default.removeItem(atPath: todo)
        try? FileManager.default.removeItem(atPath: done)
    }
    
    let t = make(todo, done, .live * { 
        $0.now = now
        $0.editor = editor
    })
    
    return (t, todo, done, tearDown)
}

let getOutput: (() -> Void) -> [String] = { block in
    let pipe = Pipe()
    let originalStdout = dup(STDOUT_FILENO)
    setvbuf(stdout, nil, _IONBF, 0)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
    
    block()
    
    fflush(stdout)
    try? pipe.fileHandleForWriting.close()
    dup2(originalStdout, STDOUT_FILENO)
    close(originalStdout)
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return [] }
    return output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).dropLast()
}


let integrationTest: () = {
    
    let now = Calendar.current.date(from: DateComponents(year: 2016, month: 1, day: 1))!
    let sut = makeSUT({ now }) { _ in }
    
    // 1. Añadir tareas
    do {
        let output = getOutput { try! sut.execute(["add", "Comprar leche"]) }
        let disk = try! String(contentsOfFile: sut.todo, encoding: .utf8)
        assert(disk == "Comprar leche\n")
        assert(output.first == "1 Comprar leche")
        
        let output2 = getOutput { try! sut.execute(["add", "Estudiar Swift"]) }
        let disk2 = try! String(contentsOfFile: sut.todo, encoding: .utf8)
        assert(disk2 == "Comprar leche\nEstudiar Swift\n")
        assert(output2.first == "2 Estudiar Swift")
    }
    
    // 3. Listar tareas creadas
    do {
        let output = getOutput { try! sut.execute(["list"]) }
        assert(output.count == 2)
        assert(output[0] == "1 Comprar leche")
        assert(output[1] == "2 Estudiar Swift")
    }
    
    // 4. Completar Tarea 1
    do {
        let expectedDatePrefix = yyyyMMddHHmmss.string(from: now)
        
        let output = getOutput { try! sut.execute(["complete", "1"]) }
        let todo = try! String(contentsOfFile: sut.todo, encoding: .utf8)
        let done = try! String(contentsOfFile: sut.done, encoding: .utf8)
        
        assert(todo == "Estudiar Swift\n")
        assert(done == "\(expectedDatePrefix) Comprar leche\n")
        assert(output.first == "Task completed")
    }
    
    // 5. Remover Tarea restante
    do {
        let output = getOutput { try! sut.execute(["remove", "1"]) }
        let disk = try! String(contentsOfFile: sut.todo, encoding: .utf8)
        assert(disk.isEmpty)
        assert(output.first == "Task removed")
    }
    
    // 6. Editar tarea
    do {
        let sut = makeSUT({ now }) { tmpPath in
            // Simula que el usuario editó el fichero en vi
            try! "tarea editada".write(toFile: tmpPath, atomically: true, encoding: .utf8)
        }
        try! sut.execute(["add", "tarea original"])
        
        let output = getOutput { try! sut.execute(["edit", "1"]) }
        let disk = try! String(contentsOfFile: sut.todo, encoding: .utf8)
        
        assert(disk == "tarea editada\n")
        assert(output.first == "Task updated: tarea editada")
        
        sut.tearDown()
    }
    
    sut.tearDown()
}()
#endif

// ==========================================
// 6. INVOCACIÓN
// ==========================================
let todoFile = FileManager.default.currentDirectoryPath + "/todo.txt"
let doneFile = FileManager.default.currentDirectoryPath + "/done.txt"
let arguments = Array(CommandLine.arguments.dropFirst())

let t = make(todoFile, doneFile, .live)

do {
    try t(arguments)
} catch {
    print(error.message)
}