import Foundation 

enum Todo {
	
	struct t {
		let line_number: Int
		let text: String
		let indent: Int
		
		var text_without_indent: String { text.trimmingCharacters(in: .whitespaces) }
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
}

private extension String {
	func left_padded(_ width: Int) -> String {
		let pad = width - self.count
		return pad > 0 ? String(repeating: " ", count: pad) + self : self
	}
}
