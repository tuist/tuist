import Basic
import Foundation

enum FileHandlerError: FatalError {
    case invalidTextEncoding(AbsolutePath)
    var description: String {
        switch self {
        case let .invalidTextEncoding(path):
            return "The file at \(path.asString) is not a utf8 text file"
        }
    }

    var type: ErrorType {
        switch self {
        case .invalidTextEncoding:
            return .bug
        }
    }
}

/// Protocol that defines the interface of an object that provides convenient
/// methods to interact with the system files and folders.
public protocol FileHandling: AnyObject {
    /// Returns the current path.
    var currentPath: AbsolutePath { get }

    /// Returns true if there's a folder or file at the given path.
    ///
    /// - Parameter path: Path to check.
    /// - Returns: True if there's a folder or file at the given path.
    func exists(_ path: AbsolutePath) -> Bool

    /// It copies a file or folder to another path.
    ///
    /// - Parameters:
    ///   - from: File/Folder to be copied.
    ///   - to: Path where the file/folder will be copied.
    /// - Throws: An error if from doesn't exist or to does.
    func copy(from: AbsolutePath, to: AbsolutePath) throws

    /// Reads a text file at the given path and returns it.
    ///
    /// - Parameter at: Path to the text file.
    /// - Returns: The content of the text file.
    /// - Throws: An error if the file doesn't exist or it's not a valid text file.
    func readTextFile(_ at: AbsolutePath) throws -> String

    func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath]
    func createFolder(_ path: AbsolutePath) throws
    func delete(_ path: AbsolutePath) throws
    func isFolder(_ path: AbsolutePath) -> Bool
    func touch(_ path: AbsolutePath) throws
}

public final class FileHandler: FileHandling {
    public init() {}

    /// Returns the current path.
    public var currentPath: AbsolutePath {
        return AbsolutePath(FileManager.default.currentDirectoryPath)
    }

    /// Returns true if there's a folder or file at the given path.
    ///
    /// - Parameter path: Path to check.
    /// - Returns: True if there's a folder or file at the given path.
    public func exists(_ path: AbsolutePath) -> Bool {
        return FileManager.default.fileExists(atPath: path.asString)
    }

    /// It copies a file or folder to another path.
    ///
    /// - Parameters:
    ///   - from: File/Folder to be copied.
    ///   - to: Path where the file/folder will be copied.
    /// - Throws: An error if from doesn't exist or to does.
    public func copy(from: AbsolutePath, to: AbsolutePath) throws {
        try FileManager.default.copyItem(atPath: from.asString, toPath: to.asString)
    }

    /// Reads a text file at the given path and returns it.
    ///
    /// - Parameter at: Path to the text file.
    /// - Returns: The content of the text file.
    /// - Throws: An error if the file doesn't exist or it's not a valid text file.
    public func readTextFile(_ at: AbsolutePath) throws -> String {
        let data = try Data(contentsOf: at.url)
        if let content = String(data: data, encoding: .utf8) {
            return content
        } else {
            throw FileHandlerError.invalidTextEncoding(at)
        }
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
