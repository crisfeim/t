// MARK: - Effects
struct Effects {
    typealias Path = String
    
    let fs: FileSystem
    let vcs: VersionControl
    let put: (String) -> Void
    let currentDirectory: () -> String
    var now: () -> Date
    var editor: (Path) throws(AppError) -> Void
    var date: String { yyyyMMddHHmmss.string(from: now()) }
    
    struct FileSystem {
        let read: (Path) throws(AppError) -> [String]
        let write: ([String], Path) throws(AppError) -> Void
        let delete: (Path) throws(AppError) -> Void
        let all: () throws(AppError) -> [Path]
    }
    
    struct VersionControl {
        let get: (Path) -> (dir: String, type: VersionControlSystem)?
        let commit: (String, VersionControlSystem, Path) throws(AppError) -> Void
    }
}

let yyyyMMddHHmmss: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMddHHmmss"
    return formatter
}()

enum VersionControlSystem: String {
    case git
    case fossil
}


// MARK: - Error
enum AppError: Error {
    case wrongLine(Int)
    case conflictingFlags
    case unhandledFlag
    case fileSystem(FileSystem)
    case editor(FileSystem)
    case unexistentProject(wrongProject: String, available: [String])
    case vcs(String)
    
    enum FileSystem {
        case notFound
        case permissionDenied
        case diskFull    
        case unknownIO(String)
    }
}

import Foundation

enum ErrorMapper {
    static func map(_ error: Error) -> AppError.FileSystem {
        let nsError = error as NSError
        
        switch (nsError.domain, nsError.code) {
            case (NSCocoaErrorDomain, NSFileReadNoSuchFileError), 
            (NSCocoaErrorDomain, NSFileNoSuchFileError),
            (NSPOSIXErrorDomain, Int(ENOENT)):
            return .notFound
            
            case (NSCocoaErrorDomain, NSFileWriteNoPermissionError), 
            (NSCocoaErrorDomain, NSFileReadNoPermissionError),
            (NSPOSIXErrorDomain, Int(EACCES)), 
            (NSPOSIXErrorDomain, Int(EPERM)):
            return .permissionDenied
            
            case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError), 
            (NSPOSIXErrorDomain, Int(ENOSPC)):
            return .diskFull
            
            default:
            return .unknownIO(nsError.localizedDescription)
        }
    }
}

extension AppError {
    var message: String {
        switch self {
            case let .wrongLine(line):
            return "line \(line) does not exist"
            case .conflictingFlags:
            return "invalid arguments"
            case .unhandledFlag:
            return "unknown command"
            case .fileSystem(.notFound):
            return "file not found"
            case .fileSystem(.permissionDenied):
            return "permission denied"
            case .fileSystem(.diskFull), .editor(.diskFull):
            return "disk full"
            case let .fileSystem(.unknownIO(description)):
            return "\(description)"
            case .editor(.notFound):
            return "editor not found"
            case .editor(.permissionDenied):
            return "editor permission denied"
            case let .editor(.unknownIO(description)):
            return "editor failed: \(description)"
            case let .unexistentProject(wrongProject, available):
            return "Project doesn't exist: \(wrongProject), available locations: \(available.reduce("") { acc, next in acc + "\n  " + next })"
            case let .vcs(description): 
            return "Commit error \(description)"
             
        }
    }
}