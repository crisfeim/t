import Foundation

enum Todo {
	struct t: Equatable {
		let line: Int
		let text: String
		let indent: Int
		let has_children: Bool
		
		var dedented: String { text.trimmingCharacters(in: .whitespaces) }
	}
	
	static func parse(from lines: [String]) -> [t] {
		lines.enumerated().compactMap { i, line in
			guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
			let indent = line.prefix(while: { $0 == "\t" }).count
			let has_children = lines.get_at(i + 1)?.contains("\t") ?? false
			return t(line: i + 1, text: line, indent: indent, has_children: has_children)
		}
	}
	
	static func list(from lines: [String]) -> [String] {
		let todos = parse(from: lines)
		if todos.isEmpty { return [] }
		let width = String(todos.map { $0.line }.max() ?? 1).count
		return todos.filter { $0.indent == 0 } .map { todo in
			let line = todo.line.description + (todo.has_children ? "*" : "")
			return "\(line.left_padded(width)) \(todo.text)"
		}
	}
	
	struct WrongLineNumber: Error {}
	
	static func add(_ text: String, to lines: [String], after line: Int) throws(WrongLineNumber) -> [String] {
		var lines = lines
		guard line >= 1 && line <= lines.count else { throw WrongLineNumber() }
		
		let ref_idx = line - 1
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
	static func remove(_ line: Int, from lines: [String]) throws(WrongLineNumber) -> (lines: [String], removed: String?) {
		guard line >= 1 && line <= lines.count else { throw WrongLineNumber() }
		var copy = lines
		let removed = copy.remove(at: line - 1).trimmingCharacters(in: .whitespaces)
		return (copy, removed)
	}
}

private extension String {
	func left_padded(_ width: Int) -> String {
		let pad = width - self.count
		return pad > 0 ? String(repeating: " ", count: pad) + self : self
	}
}

extension Array {
	func get_at(_ idx: Int) -> Element? {
		guard idx >= 0 && idx < count else { return nil }
		return self[idx]
	}
}
