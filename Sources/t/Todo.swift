import Foundation

enum Todo {
	struct t: Equatable {
		let line_number: Int
		let text: String
		let indent: Int
		
		var dedented: String { text.trimmingCharacters(in: .whitespaces) }
	}
	
	static func parse(from lines: [String]) -> [t] {
		lines.enumerated().compactMap { i, line in
			guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
			let indent = line.prefix(while: { $0 == "\t" }).count
			return t(line_number: i + 1, text: line, indent: indent)
		}
	}
	
	static func list(from lines: [String]) -> [String] {
		let todos = parse(from: lines)
		if todos.isEmpty { return [] }
		let width = String(todos.map { $0.line_number }.max() ?? 1).count
		return todos.map { todo in "\(String(todo.line_number).left_padded(width))  \(todo.text)" }
	}
	
	struct WrongLineNumber: Error {}
	
	static func add(_ text: String, to lines: [String], after line_number: Int) throws(WrongLineNumber) -> [String] {
		var lines = lines
		guard line_number >= 1 && line_number <= lines.count else {
			throw WrongLineNumber()
		}
		
		let ref_idx = line_number - 1
		let ref_indent = lines[ref_idx].prefix(while: { $0 == "\t" }).count
		let new = String(repeating: "\t", count: ref_indent + 1) + text
		
		var insert_idx = ref_idx + 1
		while insert_idx < lines.count {
			let line = lines[insert_idx]
			if line.trimmingCharacters(in: .whitespaces).isEmpty {
				insert_idx += 1
				continue
			}
			if line.prefix(while: { $0 == "\t" }).count <= ref_indent { break }
			insert_idx += 1
		}
		
		lines.insert(new, at: insert_idx)
		return lines
	}
	
	@discardableResult
	static func remove(_ line_number: Int, from lines: [String]) throws(WrongLineNumber) -> (lines: [String], removed: String?) {
		guard line_number >= 1 && line_number <= lines.count else {
			throw WrongLineNumber()
		}
		var copy = lines
		let removed = copy.remove(at: line_number - 1).trimmingCharacters(in: .whitespaces)
		return (copy, removed)
	}
}

private extension String {
	func left_padded(_ width: Int) -> String {
		let pad = width - self.count
		return pad > 0 ? String(repeating: " ", count: pad) + self : self
	}
}
