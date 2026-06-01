import Foundation

enum IO {
	static func read(_ path: String) -> [String] {
		guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
		var lines = content.components(separatedBy: "\n")
		if lines.last == "" { lines.removeLast() }
		return lines
	}
	
	static func write(_ lines: [String], to path: String) throws {
		let content = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
		try content.write(toFile: path, atomically: true, encoding: .utf8)
	}
}
