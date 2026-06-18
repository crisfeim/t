import Foundation

// ==========================================
// 1. MODELO DE DATOS Y ERRORES
// ==========================================
enum Command {
    case list
    case add(String)
    case remove(Int)
    case complete(Int)
}

typealias Args = [String]
typealias Path = String
typealias TodoPath = Path
typealias DonePath = Path

enum AppError: Error, Equatable {
    case todoFileNotFound
    case doneFileNotFound
    case wrongLine(Int)
    case conflictingFlags
    case unhandledFlag
}

// ==========================================
// 2. ESTRUCTURA DEL ENVIRONMENT (INYECCIÓN)
// ==========================================
struct FileSystem {
    let read: (Path) throws(AppError) -> [String]
    let write: ([String], Path) throws(AppError) -> Void
}

struct Environment {
    let fs: FileSystem
    let put: (String) -> Void
    let date: () -> String
}

// ==========================================
// 3. LÓGICA DE NEGOCIO (GENÉRICA Y PURA)
// ==========================================
let program: (Args, TodoPath, DonePath, Environment) throws(AppError) -> Void = { args, todoPath, donePath, env in
    let command = try parseArgs(args)
    switch command {
        case .list:
            try runList(todoPath, env)
        case let .add(todo):
            try runAdd(todoPath, todo, env)
        case let .remove(line):
            try runRemove(todoPath, line, env)
        case let .complete(line):
            try runComplete(todoPath, donePath, line, env)
    }
}

let runList: (TodoPath, Environment) throws(AppError) -> Void = { path, env  in
    let lines = try env.fs.read(path)
    lines.enumerated()
        .map { idx, content in (idx + 1).description + " " + content }
        .forEach(env.put)
}

let runAdd: (TodoPath, String, Environment) throws(AppError) -> Void = { path, todo, env in
    let todos = try env.fs.read(path)
    let updated = todos + [todo]
    try env.fs.write(updated, path)
    env.put(updated.count.description + " " + todo)
}

let runRemove: (TodoPath, Int, Environment) throws(AppError) -> Void = { path, line, env throws(AppError) in
    let todos = try env.fs.read(path)
    guard let (_, rest) = todos.removing(at: line - 1) else {
        throw AppError.wrongLine(line)
    }
    try env.fs.write(rest, path)
    env.put("Task removed")
}

let runComplete: (TodoPath, DonePath, Int, Environment) throws(AppError) -> Void = { todoPath, donePath, line, env throws(AppError) in
    let todos = try env.fs.read(todoPath)
    guard let (removed, rest) = todos.removing(at: line - 1) else {
        throw AppError.wrongLine(line)
    }
    try env.fs.write(rest, todoPath)
    let done = try env.fs.read(donePath)
    try env.fs.write(done + [env.date() + " " + removed], donePath)
    env.put("Task completed")
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
        
    default:
        throw AppError.unhandledFlag
    }
}
// ==========================================
// 5. PRODUCCIÓN: IMPLEMENTACIÓN REAL
// ==========================================
let liveEnv = Environment(
    fs: FileSystem(
        read: { path throws(AppError) in
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                throw AppError.todoFileNotFound
            }
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            return lines.last == "" ? lines.dropLast().map { $0 } : lines
        },
        write: { lines, path throws(AppError) in
            let content = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
            guard (try? content.write(toFile: path, atomically: true, encoding: .utf8)) != nil else {
                throw AppError.todoFileNotFound
            }
        }
    ),
    put: { text in print(text) },
    date: {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: Date())
    }
)

#if DEBUG
// ==========================================
// 6. TESTS: Tests suite
// ==========================================

let testEnvironment = { (mockDisk: [Path: [String]]) in
    var mockDisk: [Path: [String]] = mockDisk
    var outputs: [String] = []
    
    return (Environment(
        fs: FileSystem(
            read: { path throws(AppError) in 
                guard let mockData = mockDisk[path] else { throw .todoFileNotFound }
                return mockData
            },
            write: { lines, path throws(AppError) in 
                mockDisk[path] = lines
            }
        ),
        put: { outputs.append($0) },
        date: { "20260614183000" }
    ), { outputs }, { mockDisk })
    
}

let testRunList_Success: () = { 
    
    let (env, outputs, _) = testEnvironment(["/todo.txt": ["Comprar leche", "Estudiar Swift"]])
    
    do {
        _ = try runList("/todo.txt", env)
    } catch {
        assert(false, "Debería ser éxito")
    }
    
    assert(outputs().count == 2)
    assert(outputs()[0] == "1 Comprar leche")
    assert(outputs()[1] == "2 Estudiar Swift")
}()

let testRunList_FileNotFound: () = { 
    let (env, outputs, _) = testEnvironment([:])
    
    let result = Result { try runList("/todo.txt", env) }
    
    
    switch result {
    case .failure(let error) where error is AppError: assert(error as! AppError == .todoFileNotFound)
    default: assert(false, "Debería haber fallado")
    }
    assert(outputs().isEmpty)
}()

let testRunAdd_Success: () = {
    
    let (env, outputs, disk) = testEnvironment(["/todo.txt": ["Tarea 1"]])
    
    let result = Result { try runAdd("/todo.txt", "Tarea 2", env) }
    
    if case .failure = result { assert(false, "Debería ser éxito") }
    assert(disk()["/todo.txt"] == ["Tarea 1", "Tarea 2"])
    assert(outputs().first == "2 Tarea 2")
}()

let testRunRemove_WrongLine: () = {
    let (env, _, disk) = testEnvironment(["/todo.txt": ["Solo una tarea"]])
    let result = Result { try runRemove("/todo.txt", 5, env) }
    
    switch result {
    case .failure(let error) where error is AppError: assert(error as! AppError == .wrongLine(5))
    default: assert(false, "Debería haber fallado")
    }
    assert(disk()["/todo.txt"] == ["Solo una tarea"])
    
}()

let testRunComplete_Success: () = {    
    let (env, outputs, disk) = testEnvironment([
        "/todo.txt": ["Lavar coche", "Hacer ejercicio"],
        "/done.txt": []
    ])
    
    let result = Result { try runComplete("/todo.txt", "/done.txt", 1, env) }
    
    if case .failure = result { assert(false, "Debería ser éxito") }
    assert(disk()["/todo.txt"] == ["Hacer ejercicio"])
    assert(disk()["/done.txt"] == ["20260614183000 Lavar coche"])
    assert(outputs().first == "Task completed")
}()
#endif

// ==========================================
// 6. INVOCACIÓN
// ==========================================
let todoFile = FileManager.default.currentDirectoryPath + "/todo.txt"
let doneFile = FileManager.default.currentDirectoryPath + "/done.txt"
let arguments = Array(CommandLine.arguments.dropFirst())

do {
    try program(arguments, todoFile, doneFile, liveEnv)
} catch {
    print("error: \(error)")
}