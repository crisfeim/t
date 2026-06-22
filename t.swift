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
// 6. TESTS: Tests de integración
// ==========================================
typealias SUT = (
    execute: (Args) throws(AppError) -> Void,
    todo: TodoPath,
    done: DonePath,
    tearDown: () -> Void
)

let makeSUT: () -> SUT = {
    let tempDir = NSTemporaryDirectory()
    let uuid = UUID().uuidString
    let todo = tempDir + "todo_\(uuid).txt"
    let done = tempDir + "done_\(uuid).txt"
    
    try? "".write(toFile: todo, atomically: true, encoding: .utf8)
    try? "".write(toFile: done, atomically: true, encoding: .utf8)
    
    let tearDown = {
        try? FileManager.default.removeItem(atPath: todo)
        try? FileManager.default.removeItem(atPath: done)
    }
    
    let t = make(todo, done, liveEnv)
    
    return (t, todo, done, tearDown)
}

let captureOutput: (() throws -> Void) throws -> [String] = { block in
    let pipe = Pipe()
    let originalStdout = dup(STDOUT_FILENO)
    setvbuf(stdout, nil, _IONBF, 0)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
    
    try block()
    
    fflush(stdout)
    try? pipe.fileHandleForWriting.close()
    dup2(originalStdout, STDOUT_FILENO)
    close(originalStdout)
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return [] }
    return output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).dropLast()
}

let add: (SUT, String, Int) -> Void = { sut, todo, expectedIdx in
    let output = try! captureOutput {
        try sut.execute(["add", todo])
    }
    
    let disk = try! String(contentsOfFile: sut.todo, encoding: .utf8)
    assert(disk == "Comprar leche\n")
    assert(output.first == "\(expectedIdx) Comprar leche")
}

let integrationTest: () = {
    let sut = makeSUT()
    
    // 1. Añadir tareas
    let outputAdd1 = try! captureOutput {
        try sut.execute(["add", "Comprar leche"])
    }
    
    let diskAfterAdd1 = try! String(contentsOfFile: sut.todo, encoding: .utf8)
    assert(diskAfterAdd1 == "Comprar leche\n")
    assert(outputAdd1.first == "1 Comprar leche")
    
    let outputAdd2 = try! captureOutput {
        try sut.execute(["add", "Estudiar Swift"])
    }
    let diskAfterAdd2 = try! String(contentsOfFile: sut.todo, encoding: .utf8)
    assert(diskAfterAdd2 == "Comprar leche\nEstudiar Swift\n")
    assert(outputAdd2.first == "2 Estudiar Swift")
    
    // 3. Listar tareas creadas
    let outputList = try! captureOutput {
        try sut.execute(["list"])
    }
    assert(outputList.count == 2)
    assert(outputList[0] == "1 Comprar leche")
    assert(outputList[1] == "2 Estudiar Swift")
    
    // 4. Completar Tarea 1
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMddHHmmss"
    let expectedDatePrefix = formatter.string(from: Date())
    
    let outputComplete = try! captureOutput {
        try sut.execute(["complete", "1"])
    }
    let todoDiskAfterComplete = try! String(contentsOfFile: sut.todo, encoding: .utf8)
    let doneDiskAfterComplete = try! String(contentsOfFile: sut.done, encoding: .utf8)
    
    assert(todoDiskAfterComplete == "Estudiar Swift\n")
    assert(doneDiskAfterComplete.hasPrefix(expectedDatePrefix))
    assert(doneDiskAfterComplete.hasSuffix(" Comprar leche\n"))
    assert(outputComplete.first == "Task completed")
    
    // 5. Remover Tarea restante
    let outputRemove = try! captureOutput {
        try sut.execute(["remove", "1"])
    }
    let todoDiskAfterRemove = try! String(contentsOfFile: sut.todo, encoding: .utf8)
    assert(todoDiskAfterRemove.isEmpty)
    assert(outputRemove.first == "Task removed")
    
    sut.tearDown()
}()

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