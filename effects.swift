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