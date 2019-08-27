import Basic
import Foundation

enum FileHandlerError: FatalError {
    case invalidTextEncoding(AbsolutePath)
    case writingError(AbsolutePath)

    var description: String {
        switch self {
        case let .invalidTextEncoding(path):
            return "The file at \(path.pathString) is not a utf8 text file"
        case let .writingError(path):
            return "Couldn't write to the file \(path.pathString)"
        }
    }

    var type: ErrorType {
        switch self {
        case .invalidTextEncoding:
            return .bug
        case .writingError:
            return .abort
        }
    }
}

/// Protocol that defines the interface of an object that provides convenient
/// methods to interact with the system files and folders.
public protocol FileHandling: AnyObject {
    /// Returns the current path.
    var currentPath: AbsolutePath { get }

    /// Replaces a file/directory in a given path with another one.
    ///
    /// - Parameters:
    ///   - to: The file/directory to be replaced.
    ///   - with: The replacement file or directory.
    func replace(_ to: AbsolutePath, with: AbsolutePath) throws

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

    /// Runs the given closure passing a temporary directory to it. When the closure
    /// finishes its execution, the temporary directory gets destroyed.
    ///
    /// - Parameter closure: Closure to be executed with the temporary directory.
    /// - Throws: An error if the temporary directory cannot be created or the closure throws.
    func inTemporaryDirectory(_ closure: (AbsolutePath) throws -> Void) throws

    /// Writes a string into the given path (using the utf8 encoding)
    ///
    /// - Parameters:
    ///   - content: Content to be written.
    ///   - path: Path where the content will be written into.
    ///   - atomically: Whether the content should be written atomically.
    /// - Throws: An error if the writing fails.
    func write(_ content: String, path: AbsolutePath, atomically: Bool) throws

    func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath]
    func createSymbolicLink(_ path: AbsolutePath, destination: AbsolutePath) throws
    func createFolder(_ path: AbsolutePath) throws
    func delete(_ path: AbsolutePath) throws
    func isFolder(_ path: AbsolutePath) -> Bool
    func touch(_ path: AbsolutePath) throws
}

public final class FileHandler: FileHandling {
    /// Shared instance.
    public static var shared: FileHandling = FileHandler()

    /// File manager.
    private let fileManager: FileManager

    /// Initializes the file handler with its attributes.
    ///
    /// - Parameter fileManager: File manager instance.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Returns the current path.
    public var currentPath: AbsolutePath {
        return AbsolutePath(fileManager.currentDirectoryPath)
    }

    /// Replaces a file/directory in a given path with another one.
    ///
    /// - Parameters:
    ///   - to: The file/directory to be replaced.
    ///   - with: The replacement file or directory.
    public func replace(_ to: AbsolutePath, with: AbsolutePath) throws {
        // To support cases where the destination is on a different volume
        // we need to create a temporary directory that is suitable
        // for performing a `replaceItemAt`
        //
        // References:
        // - https://developer.apple.com/documentation/foundation/filemanager/2293212-replaceitemat
        // - https://developer.apple.com/documentation/foundation/filemanager/1407693-url
        // - https://openradar.appspot.com/50553219
        let rootTempDir = try fileManager.url(for: .itemReplacementDirectory,
                                              in: .userDomainMask,
                                              appropriateFor: to.url,
                                              create: true)
        let tempUrl = rootTempDir.appendingPathComponent("temp")
        defer { try? fileManager.removeItem(at: rootTempDir) }
        try fileManager.copyItem(at: with.url, to: tempUrl)
        _ = try fileManager.replaceItemAt(to.url, withItemAt: tempUrl)
    }

    /// Runs the given closure passing a temporary directory to it. When the closure
    /// finishes its execution, the temporary directory gets destroyed.
    ///
    /// - Parameter closure: Closure to be executed with the temporary directory.
    /// - Throws: An error if the temporary directory cannot be created or the closure throws.
    public func inTemporaryDirectory(_ closure: (AbsolutePath) throws -> Void) throws {
        let directory = try TemporaryDirectory(removeTreeOnDeinit: true)
        try closure(directory.path)
    }

    /// Returns true if there's a folder or file at the given path.
    ///
    /// - Parameter path: Path to check.
    /// - Returns: True if there's a folder or file at the given path.
    public func exists(_ path: AbsolutePath) -> Bool {
        return fileManager.fileExists(atPath: path.pathString)
    }

    /// It copies a file or folder to another path.
    ///
    /// - Parameters:
    ///   - from: File/Folder to be copied.
    ///   - to: Path where the file/folder will be copied.
    /// - Throws: An error if from doesn't exist or to does.
    public func copy(from: AbsolutePath, to: AbsolutePath) throws {
        try fileManager.copyItem(atPath: from.pathString, toPath: to.pathString)
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
    
    public func createSymbolicLink(_ path: AbsolutePath, destination: AbsolutePath) throws {
        try fileManager.createSymbolicLink(atPath: path.pathString, withDestinationPath: destination.pathString)
    }

    /// Writes a string into the given path (using the utf8 encoding)
    ///
    /// - Parameters:
    ///   - content: Content to be written.
    ///   - path: Path where the content will be written into.
    ///   - atomically: Whether the content should be written atomically.
    /// - Throws: An error if the writing fails.
    public func write(_ content: String, path: AbsolutePath, atomically: Bool) throws {
        do {
            try content.write(to: path.url, atomically: atomically, encoding: .utf8)
        } catch {}
    }

    public func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath] {
        return path.glob(glob)
    }

    public func createFolder(_ path: AbsolutePath) throws {
        try fileManager.createDirectory(at: path.url,
                                        withIntermediateDirectories: true,
                                        attributes: nil)
    }

    public func delete(_ path: AbsolutePath) throws {
        try fileManager.removeItem(atPath: path.pathString)
    }

    public func touch(_ path: AbsolutePath) throws {
        try fileManager.createDirectory(at: path.removingLastComponent().url,
                                        withIntermediateDirectories: true,
                                        attributes: nil)
        try Data().write(to: path.url)
    }

    public func isFolder(_ path: AbsolutePath) -> Bool {
        var isDirectory = ObjCBool(true)
        let exists = fileManager.fileExists(atPath: path.pathString, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
