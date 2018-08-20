import Basic
import Foundation

public protocol FileHandling: AnyObject {
    var currentPath: AbsolutePath { get }
    func exists(_ path: AbsolutePath) -> Bool
    func copy(from: AbsolutePath, to: AbsolutePath) throws
    func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath]
    func createFolder(_ path: AbsolutePath) throws
    func delete(_ path: AbsolutePath) throws
    func isFolder(_ path: AbsolutePath) -> Bool
    func touch(_ path: AbsolutePath) throws
}

public final class FileHandler: FileHandling {
    public init() {}

    public var currentPath: AbsolutePath {
        return AbsolutePath(FileManager.default.currentDirectoryPath)
    }

    public func exists(_ path: AbsolutePath) -> Bool {
        return FileManager.default.fileExists(atPath: path.asString)
    }

    public func copy(from: AbsolutePath, to: AbsolutePath) throws {
        try FileManager.default.copyItem(atPath: from.asString, toPath: to.asString)
    }

    public func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath] {
        return path.glob(glob)
    }

    public func createFolder(_ path: AbsolutePath) throws {
        try FileManager.default.createDirectory(at: path.url,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
    }

    public func delete(_ path: AbsolutePath) throws {
        try FileManager.default.removeItem(atPath: path.asString)
    }

    public func touch(_ path: AbsolutePath) throws {
        try Data().write(to: path.url)
    }

    public func isFolder(_ path: AbsolutePath) -> Bool {
        var isDirectory = ObjCBool(true)
        let exists = FileManager.default.fileExists(atPath: path.asString, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
