import Foundation

enum VCS {
    
    static func root(from path: String) -> (root: String, vcs: String)? {
        let fm = FileManager.default
        var current = path
        var fossilRoot: String? = nil
        var gitRoot: String? = nil
        
        while true {
            if fossilRoot == nil && fm.fileExists(atPath: current + "/.fslckout") {
                fossilRoot = current
            }
            if gitRoot == nil && fm.fileExists(atPath: current + "/.git") {
                gitRoot = current
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            current = parent
        }
        
        switch (fossilRoot, gitRoot) {
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
    
    static func get() -> (root: String, vcs: String)? {
        root(from: FileManager.default.currentDirectoryPath)
    }
}
