import Foundation

// ==========================================
// 1. MODELO DE DATOS Y ERRORES
// ==========================================
enum Command {
    case list(TodoPath)
    case add(String)
    case remove([Int])
    case complete(Int)
    case edit(Int)
    case all
    case project(TodoPath)
    case commit(line: Int, launchingEditor: Bool)
}

typealias Args = [String]
typealias Path = String

// ==========================================
// 3. LÓGICA DE NEGOCIO (GENÉRICA Y PURA)
// ==========================================
typealias t_cli = (Args) throws(AppError) -> Void

let make: (TodoPath, DonePath, Effects) -> t_cli = { todoPath, donePath, fx in
    return { args throws(AppError) in 
        switch try parseArgs(args, todoPath) {
            case let .list(todoPath): try runList(todoPath, fx)
            case let .add(todo): try runAdd(todoPath, todo, fx)
            case let .remove(lines): try runRemove(todoPath, lines, fx)
            case let .complete(line): try runComplete(todoPath, donePath, line, fx)
            case let .edit(line): try runEdit(todoPath, line, fx)
            case let .project(todoPath): try runListByProject(todoPath, fx)
            case let .commit(todoLine, launchingEditor): try runCommit(todoLine, todoPath, donePath, launchingEditor, fx)
            case .all: try runAll(fx)
        }
    }
}


let parseArgs: (Args, TodoPath) throws(AppError) -> Command = { args, defaultTodoPath throws(AppError) in
    guard let first = args.first else { return .list(defaultTodoPath) }
    
    switch first {
        case "list":
        guard args.count >= 1, args.count <= 2 else { throw AppError.conflictingFlags }
        if args.count == 1 {
            return .list(defaultTodoPath)
        } else {
            return .list(args[1])
        }
        
        case "add":
        guard args.count == 2 else { throw AppError.conflictingFlags }
        return .add(args[1])
        
        case "remove":
        let lines = args.dropFirst().compactMap { Int($0) }
        guard lines.count == args.count - 1 else { throw AppError.conflictingFlags }
        return .remove(lines)
        
        case "complete":
        guard args.count == 2, let line = Int(args[1])
        else { throw AppError.conflictingFlags }
        return .complete(line)
        
        case "edit":
        guard args.count == 2, let line = Int(args[1])
        else { throw AppError.conflictingFlags }
        return .edit(line)
        
        case "all":
        guard args.count == 1 else { throw AppError.conflictingFlags }
        return .all
        
        case "project":
        guard args.count == 2 else { throw AppError.conflictingFlags }
        return .project(args[1])
        
        case "commit":
        if args.count == 3, let line = Int(args[2]) {
            guard args[1] == "editor" else { throw AppError.conflictingFlags }
            return .commit(line: line, launchingEditor: true)
        }
        
        if args.count == 2, let line = Int(args[1]) {
            return .commit(line: line, launchingEditor: false)
        }
        
        throw AppError.conflictingFlags
        
        default:
        throw AppError.unhandledFlag
    }
}

struct VCS {
    private init() {}
    static let shared = VCS()
    
    let get = { (current: Path) -> (dir: String, type: VersionControlSystem)? in
        let fm = FileManager.default
        var current = current
        var fossilRoot: String? = nil
        var gitRoot: String? = nil
        while true {
            if fossilRoot == nil && fm.fileExists(atPath: current + "/.fslckout") { fossilRoot = current }
            if gitRoot == nil && fm.fileExists(atPath: current + "/.git") { gitRoot = current }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            current = parent
        }
        switch (fossilRoot, gitRoot) {
            case (let f?, let g?): return f.count >= g.count ? (f, VersionControlSystem.fossil) : (g, .git)
            case (let f?, nil): return (f, .fossil)
            case (nil, let g?): return (g, .git)
            default: return nil
        }
    }
    
    let commit: (String, VersionControlSystem, Path) throws(AppError) -> Void = { message, type, dir throws(AppError) in
        let commands: [[String]] = switch type {
            case .git: [["git", "add", "-A"], ["git", "commit", "-m", message]]
            case .fossil: [["fossil", "addremove"], ["fossil", "commit", "-m", message] ]
        }
        for args in commands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = args
            process.currentDirectoryPath = dir
            
            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe
            
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                throw AppError.vcs(error.localizedDescription)
            }
            
            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMsg = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? "VCS command failed"
                throw AppError.vcs(errorMsg)
            }
        }
    }
}


extension Effects {
    static let live = Effects(
        fs : FileSystem(
            read: { path throws(AppError) in 
                do {
                    return try IO.shared.read(path)
                } catch {
                    throw AppError.fileSystem(ErrorMapper.map(error))
                }
            },
            write: { lines, todoPath throws(AppError) in do {
                try IO.shared.write(lines, todoPath)
            } catch {
                throw AppError.fileSystem(ErrorMapper.map(error))
            }
            },
            delete: { path throws(AppError) in do { try IO.shared.delete(path) } catch { throw AppError.fileSystem(ErrorMapper.map(error)) } }, 
            all: { () throws(AppError) in do { return try IO.shared.all() } catch {
                    throw AppError.fileSystem(.unknownIO("Find failed: \(error.localizedDescription)"))
                } }
        ),
        vcs: VersionControl(get: VCS.shared.get, commit: VCS.shared.commit),
        put: { text in print(text) },
        currentDirectory: { FileManager.default.currentDirectoryPath },
        now: { Date() },
        editor: { tmpPath throws(AppError) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/vi")
            process.arguments = [tmpPath]
            do { try process.run() } catch { throw AppError.editor(ErrorMapper.map(error)) }
            tcsetpgrp(STDIN_FILENO, process.processIdentifier)
            process.waitUntilExit()
            signal(SIGTTOU, SIG_IGN)
            tcsetpgrp(STDIN_FILENO, getpgrp())
            signal(SIGTTOU, SIG_DFL)
        }
    )
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
        assert(disk == "Comprar leche")
        assert(output.first == "1 Comprar leche")
        
        let output2 = getOutput { try! sut.execute(["add", "Estudiar Swift"]) }
        let disk2 = try! String(contentsOfFile: sut.todo, encoding: .utf8)
        assert(disk2 == "Comprar leche\nEstudiar Swift")
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
        
        assert(todo == "Estudiar Swift")
        assert(done == "\(expectedDatePrefix) Comprar leche")
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
        
        assert(disk == "tarea editada")
        assert(output.first == "Task updated: tarea editada")
        
        sut.tearDown()
    }
    
    sut.tearDown()
}()
#endif

// ==========================================
// 6. INVOCACIÓN
// ==========================================
let todoFile = FileManager.default.currentDirectoryPath + "/.todo"
let doneFile = FileManager.default.currentDirectoryPath + "/.done"
let arguments = Array(CommandLine.arguments.dropFirst())

let t = make(todoFile, doneFile, .live)

do {
    try t(arguments)
} catch {
    print(error.message)
}
