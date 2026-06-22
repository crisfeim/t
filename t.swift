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
    case fileNotFound
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
    var now: () -> Date
    
    var date: String { Environment.formatter.string(from: now()) }
    
    static var formatter:  DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter
    }
}

// ==========================================
// 3. LÓGICA DE NEGOCIO (GENÉRICA Y PURA)
// ==========================================
typealias t_cli = (Args) throws(AppError) -> Void

let make: (TodoPath, DonePath, Environment) -> t_cli = { todoPath, donePath, env in
    return { args throws(AppError) in 
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
    guard let (_, rest) = todos.removing(at: line - 1) else { throw AppError.wrongLine(line) }
    try env.fs.write(rest, path)
    env.put("Task removed")
}

let runComplete: (TodoPath, DonePath, Int, Environment) throws(AppError) -> Void = { todoPath, donePath, line, env throws(AppError) in
    let todos = try env.fs.read(todoPath)
    guard let (removed, rest) = todos.removing(at: line - 1) else { throw AppError.wrongLine(line) }
    let done = (try? env.fs.read(donePath)) ?? []
    try env.fs.write(done + [env.date + " " + removed], donePath)
    try env.fs.write(rest, todoPath)
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
    now: { Date() }
)

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

let makeSUT: (@escaping () -> Date) -> SUT = { now in
    let tempDir = NSTemporaryDirectory()
    let uuid = UUID().uuidString
    let todo = tempDir + "todo_\(uuid).txt"
    let done = tempDir + "done_\(uuid).txt"
    
    try? "".write(toFile: todo, atomically: true, encoding: .utf8)
    
    let tearDown = {
        try? FileManager.default.removeItem(atPath: todo)
        try? FileManager.default.removeItem(atPath: done)
    }
    
    let t = make(todo, done, liveEnv * { $0.now = now })
    
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
    let sut = makeSUT({ now })
    
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
        let expectedDatePrefix = Environment.formatter.string(from: now)
        
        let output = getOutput { try! sut.execute(["complete", "1"]) }
        let todo = try! String(contentsOfFile: sut.todo, encoding: .utf8)
        let done = try! String(contentsOfFile: sut.done, encoding: .utf8)
        
        assert(todo == "Estudiar Swift\n")
        assert(done.hasPrefix(expectedDatePrefix))
        assert(done.hasSuffix(" Comprar leche\n"))
        assert(output.first == "Task completed")
    }
    
    // 5. Remover Tarea restante
    do {
        let output = getOutput { try! sut.execute(["remove", "1"]) }
        let disk = try! String(contentsOfFile: sut.todo, encoding: .utf8)
        assert(disk.isEmpty)
        assert(output.first == "Task removed")
    }
    
    sut.tearDown()
}()



// Helpers
infix operator *: MultiplicationPrecedence
func *<A>(lhs: A, rhs: (inout A) -> Void) -> A {
    var copy = lhs
    rhs(&copy)
    return copy
}

#endif

// ==========================================
// 6. INVOCACIÓN
// ==========================================
let todoFile = FileManager.default.currentDirectoryPath + "/todo.txt"
let doneFile = FileManager.default.currentDirectoryPath + "/done.txt"
let arguments = Array(CommandLine.arguments.dropFirst())

let t = make(todoFile, doneFile, liveEnv)

do {
    try t(arguments)
} catch {
    print("error: \(error)")
}


