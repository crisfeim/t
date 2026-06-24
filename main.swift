import Foundation

enum Command {
    case list(TodoPath)
    case add(TodoPath, String)
    case remove(TodoPath, [Int])
    case complete(TodoPath, Int)
    case edit(TodoPath, Int)
    case all
    case commit(TodoPath, line: Int, editMsg: Bool)
    case projectsAll
}

typealias Args   = [String]
typealias Path   = String
typealias Parser = (Args, TodoPath) throws(T.Error) -> Command

let make: (TodoPath, DonePath, Effects.All) -> T.CLI = { todoPath, donePath, fx in
    return { args throws(T.Error) in 
        switch try projectPreparsing(fx.io, parse)(args, todoPath) {
            case let .list(path):               try runList(path, fx)
            case let .add(path, todo):          try runAdd(path, todo, fx)
            case let .remove(path, lines):      try runRemove(path, lines, fx)
            case let .complete(path, line):     try runComplete(path, donePath, line, fx)
            case let .edit(path, line):         try runEdit(path, line, fx)
            case let .commit(path, line, edit): try runCommit(line, path, donePath, edit, fx)
            case .all:                          try runAll(fx)
            case .projectsAll: try runProjectsList(fx)
        }
    }
}

// Preparsing decorator
// Allows global project manipulation
// Ej: t project cristian add "new todo" -> Adds todo in ~/cristian/.todo if exists.
let projectPreparsing: (Effects.IO, @escaping Parser) -> Parser = { fx, parser in
    return { args, todoPath throws(T.Error) in
        guard args.first == "project" else { return try parser(args, todoPath) }
        
        guard args.count >= 2 else { throw .conflictingFlags }
        let projectName = args[1]
        
        let todoFiles = try fx.all()
        
        guard let projectTodoPath = todoFiles.filter({ $0.contains(projectName) }) |> sortMatches |> first else {
            throw .notFound(projectName, available: todoFiles)
        }
        
        let remainingArgs = args.dropFirst(2)
        let finalArgs = remainingArgs.isEmpty ? ["list"] : Array(remainingArgs)
        
        return try parser(finalArgs, projectTodoPath)
    }
}

let parse: Parser = { args, todoPath throws(T.Error) in
    guard let first = args.first else { return .list(todoPath) }
    
    switch first {
        case "list":
        guard args.count >= 1, args.count <= 2 else { throw .conflictingFlags }
        if args.count == 1 {
            return .list(todoPath)
        } else {
            return .list(args[1])
        }
        
        case "add", "new":
        guard args.count == 2 else { throw .conflictingFlags }
        return .add(todoPath, args[1])
        
        case "remove", "rm":
        let lines = args.dropFirst().compactMap { Int($0) }
        guard lines.count == args.count - 1 else { throw .conflictingFlags }
        return .remove(todoPath, lines)
        
        case "complete":
        guard args.count == 2, let line = Int(args[1])
        else { throw .conflictingFlags }
        return .complete(todoPath, line)
        
        case "edit":
        guard args.count == 2, let line = Int(args[1])
        else { throw .conflictingFlags }
        return .edit(todoPath, line)
        
        case "all":
        guard args.count == 1 else { throw .conflictingFlags }
        return .all
        
        case "commit":
        if args.count == 3, let line = Int(args[2]) {
            guard args[1] == "editor" else { throw .conflictingFlags }
            return .commit(todoPath, line: line, editMsg: true)
        }
        
        if args.count == 2, let line = Int(args[1]) {
            return .commit(todoPath, line: line, editMsg: false)
        }
        
        throw .conflictingFlags
        
        case "projects":
        guard args.count == 1 else { throw .conflictingFlags }
        return .projectsAll
        
        default:
        throw .unhandledFlag
    }
}

let liveFx = Effects.All(
    io: (
        read  : IO.read   |> rethrow(T.Error.fs),
        write : IO.write  |> rethrow(T.Error.fs),
        delete: IO.delete |> rethrow(T.Error.fs),
        all   : IO.all    |> rethrow(T.Error.fsUnknown)
    ),
    vcs: (
        get:    VCS.get, 
        commit: VCS.commit |> rethrow(T.Error.vcs)
    ),
    put: { text in print(text) },
    currentDirectory: { FileManager.default.currentDirectoryPath },
    now: { Date() },
    editor: Editor.run |> rethrow(T.Error.editor)
)



// MARK: - CLI
extension T {
    static func run() {
        let todoFile = FileManager.default.currentDirectoryPath + "/.todo"
        let doneFile = FileManager.default.currentDirectoryPath + "/.done"
        let arguments = Array(CommandLine.arguments.dropFirst())
        
        let t = make(todoFile, doneFile, liveFx)
        do {
            try t(arguments)
        } catch {
            print(error.message)
        }
    }
}

#if RELEASE
T.run()
#endif

// MARK: - Helpers
func rethrow<each T, R, E: Error>(
    _ appError: @escaping (Error) -> E
) -> (@escaping (repeat each T) throws -> R) -> (repeat each T) throws(E) -> R {
    return { (method: @escaping (repeat each T) throws -> R) in
        return { (param: repeat each T) throws(E) in
            do {
                return try method(repeat each param)
            } catch {
                throw appError(error)
            }
        }
    }
}

func first<T>(array: Array<T>) -> T? { array.first }


// MARK: - Tests
#if DEBUG
typealias SUT = (
    execute: (Args) throws(T.Error) -> Void,
    todo: TodoPath,
    done: DonePath,
    tearDown: () -> Void
)

let makeSUT: (Effects.All) -> SUT = { fx in
    let tempDir = NSTemporaryDirectory()
    let uuid = UUID().uuidString
    let todo = tempDir + "todo_\(uuid).txt"
    let done = tempDir + "done_\(uuid).txt"
    
    try? "".write(toFile: todo, atomically: true, encoding: .utf8)
    
    let tearDown = {
        try? FileManager.default.removeItem(atPath: todo)
        try? FileManager.default.removeItem(atPath: done)
    }
    
    let t = make(todo, done, fx)
    
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



let test_parserErrors: () = {
    let sut = makeSUT(liveFx)
    
    assertThrows(.unhandledFlag, { () throws(T.Error) in try sut.execute(["invalid_command"]) })
    
    assertThrows(.conflictingFlags, { () throws(T.Error) in try sut.execute(["list", "fichero.txt", "extra"]) })
    
    assertThrows(.conflictingFlags, { () throws(T.Error) in try sut.execute(["add"]) })
    assertThrows(.conflictingFlags, { () throws(T.Error) in try sut.execute(["add", "tarea", "extra"]) })
    
    assertThrows(.conflictingFlags, { () throws(T.Error) in try sut.execute(["remove", "1", "abc", "3"]) })
    
    assertThrows(.conflictingFlags, { () throws(T.Error) in try sut.execute(["complete"]) })
    assertThrows(.conflictingFlags, { () throws(T.Error) in try sut.execute(["complete", "abc"]) })
    
    assertThrows(.conflictingFlags, { () throws(T.Error) in try sut.execute(["edit"]) })
    assertThrows(.conflictingFlags, { () throws(T.Error) in try sut.execute(["edit", "abc"]) })
    
    assertThrows(.conflictingFlags, { () throws(T.Error) in try sut.execute(["all", "extra"]) })
    
    assertThrows(.conflictingFlags, { () throws(T.Error) in try sut.execute(["project"]) })
    
    assertThrows(.conflictingFlags, { () throws(T.Error) in try sut.execute(["commit"]) })
    assertThrows(.conflictingFlags, { () throws(T.Error) in try sut.execute(["commit", "wrong_flag", "1"]) })
    assertThrows(.conflictingFlags, { () throws(T.Error) in try sut.execute(["commit", "editor", "abc"]) })
    
    sut.tearDown()
}()

let test_lineBounds: () = {
    let sut = makeSUT(liveFx)
    try! sut.execute(["add", "Single task"])
    
    assertThrows(.wrongLine(0), { () throws(T.Error) in try sut.execute(["complete", "0"]) })
    assertThrows(.wrongLine(2), { () throws(T.Error) in try sut.execute(["complete", "2"]) })
    
    assertThrows(.wrongLine(0), { () throws(T.Error) in try sut.execute(["edit", "0"]) })
    assertThrows(.wrongLine(2), { () throws(T.Error) in try sut.execute(["edit", "2"]) })
    
    assertThrows(.wrongLine(0), { () throws(T.Error) in try sut.execute(["commit", "0"]) })
    assertThrows(.wrongLine(2), { () throws(T.Error) in try sut.execute(["commit", "2"]) })
    
    sut.tearDown()
}()

let test_versionControlIntegration: () = {    
    // CASE 1: Not a repository error
    do {
        let sut = makeSUT(liveFx * { $0.vcs.get = { _ in nil } })
        assertThrows(.vcs("Not a repository"), { () throws(T.Error) in try sut.execute(["commit", "1"]) })
        sut.tearDown()
    }
    
    // CASE 2: Fossil integration
    do {
        var receivedMessage = ""
        var receivedSystem = ""
        
        let sut = makeSUT(
            liveFx * {
                $0.vcs.get = { _ in (dir: "/mock/repo", type: "fossil") }
                $0.vcs.commit = { msg, sys, _ in 
                    receivedMessage = msg
                    receivedSystem = sys
                }
            }
        )
        
        try! sut.execute(["add", "Fossil task"])
        try! sut.execute(["commit", "1"])
        
        assert(receivedMessage == "Fossil task")
        assert(receivedSystem == "fossil")
        
        let todoDisk = try! String(contentsOfFile: sut.todo, encoding: .utf8)
        let doneDisk = try! String(contentsOfFile: sut.done, encoding: .utf8)
        assert(todoDisk.isEmpty)
        assert(doneDisk.contains("Fossil task"))
        
        sut.tearDown()
    }
    
    // CASE 3: Commit via Editor modifications
    do {
        var receivedMessage = ""
        
        let sut = makeSUT(
            liveFx * {
                $0.vcs.get = { _ in (dir: "/mock/repo", type: "git") }
                $0.vcs.commit = { msg, _, _ in 
                    receivedMessage = msg
                }
                $0.editor = { tmpPath in
                    try! "Custom commit message from editor".write(toFile: tmpPath, atomically: true, encoding: .utf8)
                }
            }
        )
        
        try! sut.execute(["add", "Original task text"])
        try! sut.execute(["commit", "editor", "1"])
        
        assert(receivedMessage == "Custom commit message from editor")
        
        sut.tearDown()
    }
}()

let test_remoteProjectManagement: () = {
    // 1: Comando básico 'project <nombre>' debe transformarse en 'list' implícito
    do {
        var readCalledWithPath = ""
        let mockFx = liveFx * {
            $0.io.all = { ["/proyectos/cristian/.todo", "/proyectos/otro/.todo"] }
            $0.io.read = { path in 
                readCalledWithPath = path
                return []
            }
        }
        let sut = makeSUT(mockFx)
        
        try! sut.execute(["project", "cristian"])
        assert(readCalledWithPath == "/proyectos/cristian/.todo")
        
        sut.tearDown()
    }
    
    // Escenario 2: Subcomandos remotos pasados a través de 'project'
    do {
        var writeCalledWithPath = ""
        var contentWritten = ""
        let mockFx = liveFx * {
            $0.io.all = { ["/proyectos/cristian/.todo"] }
            $0.io.read = { _ in [] }
            $0.io.write = { content, path in
                writeCalledWithPath = path
                contentWritten = content.joined()
            }
        }
        let sut = makeSUT(mockFx)
        
        try! sut.execute(["project", "cristian", "add", "Nueva tarea remota"])
        assert(writeCalledWithPath == "/proyectos/cristian/.todo")
        assert(contentWritten == "Nueva tarea remota")
        
        sut.tearDown()
    }
    
    // Escenario 3: Desempate por orden de pertinencia (jerarquía y longitud)
    do {
        var readCalledWithPath = ""
        let mockFx = liveFx * {
            $0.io.all = { [
                "/Users/cristian/💻/a/.todo", 
                "/Users/cristian/💻/t/.todo",
                "/Users/cristian/💻/sub/nivel/extra/cristian/.todo"
            ] }
            $0.io.read = { path in
                readCalledWithPath = path
                return []
            }
        }
        let sut = makeSUT(mockFx)
        
        try! sut.execute(["project", "cristian"])
        assert(readCalledWithPath == "/Users/cristian/💻/a/.todo")
        
        sut.tearDown()
    }
    
    // Escenario 4: Errores esperados lanzados desde el decorador
    do {
        let mockFx = liveFx * { $0.io.all = { ["/proyectos/otro/.todo"] } }
        let sut = makeSUT(mockFx)
        
        assertThrows(.notFound("cristian", available: ["/proyectos/otro/.todo"]), { () throws(T.Error) in
            try sut.execute(["project", "cristian"])
        })
        
        sut.tearDown()
    }
}()

let test_projectsCommand: () = {
    // Escenario 1: Listar múltiples proyectos con ordenación e indentación correcta
    do {
        let mockFx = liveFx * {
            $0.io.all = { [
                "/Users/cristian/b/.todo",
                "/Users/cristian/a/.todo"
            ] }
            $0.io.read = { path in
                if path.contains("a/.todo") {
                    return ["Comprar leche","Estudiar Swift"]
                } else {
                    return ["Fossil task"]
                }
            }
        }
        
        let sut = makeSUT(mockFx)
        
        let output = getOutput { try! sut.execute(["projects"]) }
        
        // Verifica que ordena primero por 'a/.todo' debido al desempate alfabético
        assert(output[0] == "/Users/cristian/a/.todo")
        assert(output[1] == "    1 Comprar leche")
        assert(output[2] == "    2 Estudiar Swift")
        assert(output[3] == "/Users/cristian/b/.todo")
        assert(output[4] == "    1 Fossil task")
        
        sut.tearDown()
    }
    
    // Escenario 2: Proyectos vacíos no deben listar tareas indentadas
    do {
        let mockFx = liveFx * {
            $0.io.all = { ["/Users/cristian/empty/.todo"] }
            $0.io.read = { _ in [] }
        }
        
        let sut = makeSUT(mockFx)
        let output = getOutput { try! sut.execute(["projects"]) }
        
        assert(output.count == 1)
        assert(output[0] == "/Users/cristian/empty/.todo")
        
        sut.tearDown()
    }
    
    // Escenario 3: Pasar argumentos extra a 'projects' debe lanzar .conflictingFlags
    do {
        let sut = makeSUT(liveFx)
        
        assertThrows(.conflictingFlags, { () throws(T.Error) in 
            try sut.execute(["projects", "extra_arg"]) 
        })
        
        sut.tearDown()
    }
}()

let test_integration: () = {
    
    let now = Calendar.current.date(from: DateComponents(year: 2016, month: 1, day: 1))!
    
    var editor = { (p: String) in try! "tarea editada".write(toFile: p, atomically: true, encoding: .utf8) }
     
    let sut = makeSUT(liveFx * { 
        $0.now = { now }
        $0.editor = { editor($0) }
    })
    
    // 1. Añadir tareas
    do {
        do {
            let output = getOutput { try! sut.execute(["add", "Comprar leche"]) }
            let disk = try! String(contentsOfFile: sut.todo, encoding: .utf8)
            assert(disk == "Comprar leche")
            assert(output.first == "1 Comprar leche")
        }
        
        do {
            let output = getOutput { try! sut.execute(["add", "Estudiar Swift"]) }
            let disk = try! String(contentsOfFile: sut.todo, encoding: .utf8)
            assert(disk == "Comprar leche\nEstudiar Swift")
            assert(output.first == "2 Estudiar Swift")
        }
        
        do {
            let output = getOutput { try! sut.execute(["add", "Estudiar Concurrencia"]) }
            let disk = try! String(contentsOfFile: sut.todo, encoding: .utf8)
            assert(disk == "Comprar leche\nEstudiar Swift\nEstudiar Concurrencia")
            assert(output.first == "3 Estudiar Concurrencia")
        }
        
    }
    
    // 3. Listar tareas creadas
    do {
        let output = getOutput { try! sut.execute(["list"]) }
        assert(output.count == 3)
        assert(output[0] == "1 Comprar leche")
        assert(output[1] == "2 Estudiar Swift")
        assert(output[2] == "3 Estudiar Concurrencia")
    }
    
    // 4. Completar Tarea 1
    do {
        let expectedDatePrefix = yyyyMMddHHmmss.string(from: now)
        
        let output = getOutput { try! sut.execute(["complete", "1"]) }
        let todo = try! String(contentsOfFile: sut.todo, encoding: .utf8)
        let done = try! String(contentsOfFile: sut.done, encoding: .utf8)
        
        assert(todo == "Estudiar Swift\nEstudiar Concurrencia")
        assert(done == "\(expectedDatePrefix) Comprar leche")
        assert(output.first == "Todo completed")
    }
    
    // 5. Remover Tarea restante
    do {
        let output = getOutput { try! sut.execute(["remove", "1"]) }
        let disk = try! String(contentsOfFile: sut.todo, encoding: .utf8)
        assert(disk == "Estudiar Concurrencia")
        assert(output.first == "Todo removed")
    }
    
    // 6. Editar tarea
    do {
        let output = getOutput { try! sut.execute(["edit", "1"]) }
        let disk = try! String(contentsOfFile: sut.todo, encoding: .utf8)
        
        assert(disk == "tarea editada")
        assert(output.first == "Todo updated: tarea editada")
    }
    
    // 7. Ediing edge cases
    do {
        do {
            editor = { try! "".write(toFile: $0, atomically: true, encoding: .utf8) }
            let output = getOutput { try! sut.execute(["edit", "1"])}
            let disk = try! String(contentsOfFile: sut.todo, encoding: .utf8)
            assert(disk == "tarea editada")
            assert(output.first == "No changes")
        }
        
        do {
            editor = { try! "tarea editada".write(toFile: $0, atomically: true, encoding: .utf8) }
            let output = getOutput { try! sut.execute(["edit", "1"])}
            let disk = try! String(contentsOfFile: sut.todo, encoding: .utf8)
            assert(disk == "tarea editada")
            assert(output.first == "No changes")
        }
    }
    
    sut.tearDown()
}()
#endif