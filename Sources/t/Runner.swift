import Foundation

enum Runner {
	@discardableResult
	static func run(_ command: String, inDirectory directory: String? = nil) -> String {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/zsh")
		process.arguments = ["-c", command]
		if let dir = directory { process.currentDirectoryURL = URL(fileURLWithPath: dir) }
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = Pipe()
		try? process.run()
		process.waitUntilExit()
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
	}
}
