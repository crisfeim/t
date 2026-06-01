import Foundation

enum VCS {
	
	static func get(from path: String) -> (dir: String, vcs: String)? {
		let fm = FileManager.default
		var current = path
		var fossil_root: String? = nil
		var git_root: String? = nil
		
		while true {
			if fossil_root == nil && fm.fileExists(atPath: current + "/.fslckout") {
				fossil_root = current
			}
			if git_root == nil && fm.fileExists(atPath: current + "/.git") {
				git_root = current
			}
			let parent = (current as NSString).deletingLastPathComponent
			if parent == current { break }
			current = parent
		}
		
		switch (fossil_root, git_root) {
		case (let f?, let g?):
			return f.count >= g.count ? (f, "fossil") : (g, "git")
		case (let f?, nil):
			return (f, "fossil")
		case (nil, let g?):
			return (g, "git")
		default:
			return nil
		}
	}
	
	static func get() -> (dir: String, vcs: String)? {
		get(from: FileManager.default.currentDirectoryPath)
	}
}
