import Foundation

struct IO {
    private init() {}
    static let shared = IO()
    
    let read = { path throws in
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.last == "" ? lines.dropLast().map { $0 } : lines
    }
    
    let write: ([String], String) throws -> Void = { lines, path throws in
        let content = lines.isEmpty ? "" : lines.joined(separator: "\n")
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
    
    let delete = { path in try FileManager.default.removeItem(atPath: path) }
    
    let all = { () throws -> [String] in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        let homeDir = NSHomeDirectory()
        process.currentDirectoryPath = homeDir
        process.arguments = [
            ".", "(", "-path", "./Library", "-o", "-path", "./Music", "-o", "-path", "./Pictures", "-o", "-path", "./Movies", "-o", "-path", "./Documents", "-o", "-path", "./Library/*", ")", "-prune",
            "-o", "-type", "d", "-path", "*/.*", "-prune", "-o", "-type", "f", "-name", ".todo*", "-print"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(separator: "\n").map(String.init).map { $0.replacingOccurrences(of: ".", with: homeDir, options: .anchored) }
    }
}

struct VCS {
    private init() {}
    static let shared = VCS()
    typealias Path   = String
    enum System {
        case git
        case fossil
    }
    
    typealias t = (dir: String, type: System)
    
    let get = { (current: Path) -> t? in
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
            case (let f?, let g?): return f.count >= g.count ? (f, .fossil) : (g, .git)
            case (let f?, nil): return (f, .fossil)
            case (nil, let g?): return (g, .git)
            default: return nil
        }
    }
    
    let commit: (String, System, Path) throws -> Void = { message, type, dir throws in
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
        
            try process.run()
            process.waitUntilExit()
        }
    }
}
