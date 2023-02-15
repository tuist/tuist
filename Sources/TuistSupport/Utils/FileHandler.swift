import CryptoKit
import Foundation
import TSCBasic
import ZIPFoundation

public enum FileHandlerError: FatalError, Equatable {
    case invalidTextEncoding(AbsolutePath)
    case writingError(AbsolutePath)
    case fileNotFound(AbsolutePath)
    case unreachableFileSize(AbsolutePath)
    case expectedAFile(AbsolutePath)

    public var description: String {
        switch self {
        case let .invalidTextEncoding(path):
            return "The file at \(path.pathString) is not a utf8 text file"
        case let .writingError(path):
            return "Couldn't write to the file \(path.pathString)"
        case let .fileNotFound(path):
            return "File not found at \(path.pathString)"
        case let .unreachableFileSize(path):
            return "Could not get the file size at path \(path.pathString)"
        case let .expectedAFile(path):
            return "Could not find a file at path \(path.pathString))"
        }
    }

    public var type: ErrorType {
        switch self {
        case .invalidTextEncoding:
            return .bug
        case .writingError, .fileNotFound, .unreachableFileSize, .expectedAFile:
            return .abort
        }
    }
}

/// Protocol that defines the interface of an object that provides convenient
/// methods to interact with the system files and folders.
public protocol FileHandling: AnyObject {
    /// Returns the current path.
    var currentPath: AbsolutePath { get }

    /// Returns `AbsolutePath` to home directory
    var homeDirectory: AbsolutePath { get }

    func replace(_ to: AbsolutePath, with: AbsolutePath) throws
    func exists(_ path: AbsolutePath) -> Bool
    func move(from: AbsolutePath, to: AbsolutePath) throws
    func copy(from: AbsolutePath, to: AbsolutePath) throws
    func readFile(_ at: AbsolutePath) throws -> Data
    func readTextFile(_ at: AbsolutePath) throws -> String
    func readPlistFile<T: Decodable>(_ at: AbsolutePath) throws -> T
    /// Determine temporary directory either default for user or specified by ENV variable
    func determineTemporaryDirectory() throws -> AbsolutePath
    func temporaryDirectory() throws -> AbsolutePath
    func inTemporaryDirectory(_ closure: @escaping (AbsolutePath) async throws -> Void) async throws
    func inTemporaryDirectory(_ closure: (AbsolutePath) throws -> Void) throws
    func inTemporaryDirectory(removeOnCompletion: Bool, _ closure: (AbsolutePath) throws -> Void) throws
    func inTemporaryDirectory<Result>(_ closure: (AbsolutePath) throws -> Result) throws -> Result
    func inTemporaryDirectory<Result>(removeOnCompletion: Bool, _ closure: (AbsolutePath) throws -> Result) throws -> Result
    func write(_ content: String, path: AbsolutePath, atomically: Bool) throws
    func locateDirectoryTraversingParents(from: AbsolutePath, path: String) -> AbsolutePath?
    func locateDirectory(_ path: String, traversingFrom from: AbsolutePath) -> AbsolutePath?
    func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath]
    func throwingGlob(_ path: AbsolutePath, glob: String) throws -> [AbsolutePath]
    func linkFile(atPath: AbsolutePath, toPath: AbsolutePath) throws
    func createFolder(_ path: AbsolutePath) throws
    func delete(_ path: AbsolutePath) throws
    func isFolder(_ path: AbsolutePath) -> Bool
    func touch(_ path: AbsolutePath) throws
    func contentsOfDirectory(_ path: AbsolutePath) throws -> [AbsolutePath]
    func urlSafeBase64MD5(path: AbsolutePath) throws -> String
    func fileSize(path: AbsolutePath) throws -> UInt64
    func changeExtension(path: AbsolutePath, to newExtension: String) throws -> AbsolutePath
    func resolveSymlinks(_ path: AbsolutePath) throws -> AbsolutePath
    func fileAttributes(at path: AbsolutePath) throws -> [FileAttributeKey: Any]
    func filesAndDirectoriesContained(in path: AbsolutePath) -> [AbsolutePath]?
    func zipItem(at sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws
    func unzipItem(at sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws
}

public class FileHandler: FileHandling {
    // MARK: - Attributes

    public static var shared: FileHandling = FileHandler()
    private let fileManager: FileManager
    private let propertyListDecoder = PropertyListDecoder()

    /// Initializes the file handler with its attributes.
    ///
    /// - Parameter fileManager: File manager instance.
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public var currentPath: AbsolutePath {
        try! AbsolutePath(validating: fileManager.currentDirectoryPath) // swiftlint:disable:this force_try
    }

    public var homeDirectory: AbsolutePath {
        try! AbsolutePath(validating: NSHomeDirectory()) // swiftlint:disable:this force_try
    }

    public func replace(_ to: AbsolutePath, with: AbsolutePath) throws {
        // To support cases where the destination is on a different volume
        // we need to create a temporary directory that is suitable
        // for performing a `replaceItemAt`
        //
        // References:
        // - https://developer.apple.com/documentation/foundation/filemanager/2293212-replaceitemat
        // - https://developer.apple.com/documentation/foundation/filemanager/1407693-url
        // - https://openradar.appspot.com/50553219
        let rootTempDir = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: to.url,
            create: true
        )
        let tempUrl = rootTempDir.appendingPathComponent("temp")
        defer { try? fileManager.removeItem(at: rootTempDir) }
        try fileManager.copyItem(at: with.url, to: tempUrl)
        _ = try fileManager.replaceItemAt(to.url, withItemAt: tempUrl)
    }

    public func temporaryDirectory() throws -> AbsolutePath {
        let directory = try TemporaryDirectory(removeTreeOnDeinit: false)
        return directory.path
    }

    public func determineTemporaryDirectory() throws -> AbsolutePath {
        try determineTempDirectory()
    }

    public func inTemporaryDirectory<Result>(_ closure: (AbsolutePath) throws -> Result) throws -> Result {
        try withTemporaryDirectory(removeTreeOnDeinit: true, closure)
    }

    public func inTemporaryDirectory(removeOnCompletion: Bool, _ closure: (AbsolutePath) throws -> Void) throws {
        try withTemporaryDirectory(removeTreeOnDeinit: removeOnCompletion, closure)
    }

    public func inTemporaryDirectory(_ closure: (AbsolutePath) throws -> Void) throws {
        try withTemporaryDirectory(removeTreeOnDeinit: true, closure)
    }

    public func inTemporaryDirectory(_ closure: @escaping (AbsolutePath) async throws -> Void) async throws {
        let directory = try TemporaryDirectory(removeTreeOnDeinit: true)
        try await closure(directory.path)
    }

    public func inTemporaryDirectory<Result>(
        removeOnCompletion: Bool,
        _ closure: (AbsolutePath) throws -> Result
    ) throws -> Result {
        try withTemporaryDirectory(removeTreeOnDeinit: removeOnCompletion, closure)
    }

    public func exists(_ path: AbsolutePath) -> Bool {
        let exists = fileManager.fileExists(atPath: path.pathString)
        logger.debug("Checking if \(path) exists... \(exists)")
        return exists
    }

    public func copy(from: AbsolutePath, to: AbsolutePath) throws {
        logger.debug("Copying file from \(from) to \(to)")
        try fileManager.copyItem(atPath: from.pathString, toPath: to.pathString)
    }

    public func move(from: AbsolutePath, to: AbsolutePath) throws {
        logger.debug("Moving file from \(from) to \(to)")
        try fileManager.moveItem(atPath: from.pathString, toPath: to.pathString)
    }

    public func readFile(_ at: AbsolutePath) throws -> Data {
        logger.debug("Reading contents of file at path \(at)")
        return try Data(contentsOf: at.url)
    }

    public func readTextFile(_ at: AbsolutePath) throws -> String {
        logger.debug("Reading contents of text file at path \(at)")
        let data = try Data(contentsOf: at.url)
        if let content = String(data: data, encoding: .utf8) {
            return content
        } else {
            throw FileHandlerError.invalidTextEncoding(at)
        }
    }

    public func readPlistFile<T: Decodable>(_ at: AbsolutePath) throws -> T {
        logger.debug("Reading contents of plist file at path \(at)")
        guard let data = fileManager.contents(atPath: at.pathString) else {
            throw FileHandlerError.fileNotFound(at)
        }
        return try propertyListDecoder.decode(T.self, from: data)
    }

    public func linkFile(atPath: AbsolutePath, toPath: AbsolutePath) throws {
        logger.debug("Creating a link from \(atPath) to \(toPath)")
        try fileManager.linkItem(atPath: atPath.pathString, toPath: toPath.pathString)
    }

    public func write(_ content: String, path: AbsolutePath, atomically: Bool) throws {
        logger.debug("Writing contents to file \(path) atomically \(atomically)")
        do {
            try content.write(to: path.url, atomically: atomically, encoding: .utf8)
        } catch {}
    }

    public func locateDirectory(_ path: String, traversingFrom from: AbsolutePath) -> AbsolutePath? {
        logger.debug("Traversing \(from) to locate \(path)")
        let extendedPath = from.appending(RelativePath(path))
        if exists(extendedPath) {
            return extendedPath
        } else if !from.isRoot {
            return locateDirectory(path, traversingFrom: from.parentDirectory)
        } else {
            return nil
        }
    }

    public func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath] {
        path.glob(glob)
    }

    public func throwingGlob(_ path: AbsolutePath, glob: String) throws -> [AbsolutePath] {
        try path.throwingGlob(glob)
    }

    public func createFolder(_ path: AbsolutePath) throws {
        logger.debug("Creating folder at path \(path)")
        try fileManager.createDirectory(
            at: path.url,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    public func delete(_ path: AbsolutePath) throws {
        logger.debug("Deleting item at path \(path)")
        if exists(path) {
            try fileManager.removeItem(atPath: path.pathString)
        }
    }

    public func touch(_ path: AbsolutePath) throws {
        logger.debug("Touching \(path)")
        try fileManager.createDirectory(
            at: path.removingLastComponent().url,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try Data().write(to: path.url)
    }

    public func isFolder(_ path: AbsolutePath) -> Bool {
        var isDirectory = ObjCBool(true)
        let exists = fileManager.fileExists(atPath: path.pathString, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    public func locateDirectoryTraversingParents(from: AbsolutePath, path: String) -> AbsolutePath? {
        logger.debug("Traversing \(from) to locate \(path)")

        let configPath = from.appending(component: path)

        let root = try! AbsolutePath(validating: "/") // swiftlint:disable:this force_try
        if FileHandler.shared.exists(configPath) {
            return configPath
        } else if from == root {
            return nil
        } else {
            return locateDirectoryTraversingParents(from: from.parentDirectory, path: path)
        }
    }

    public func contentsOfDirectory(_ path: AbsolutePath) throws -> [AbsolutePath] {
        try fileManager.contentsOfDirectory(atPath: path.pathString).map { try AbsolutePath(validating: $0, relativeTo: path) }
    }

    public func createSymbolicLink(at path: AbsolutePath, destination: AbsolutePath) throws {
        try fileManager.createSymbolicLink(atPath: path.pathString, withDestinationPath: destination.pathString)
    }

    public func resolveSymlinks(_ path: AbsolutePath) throws -> AbsolutePath {
        try TSCBasic.resolveSymlinks(path)
    }

    public func fileAttributes(at path: AbsolutePath) throws -> [FileAttributeKey: Any] {
        try fileManager.attributesOfItem(atPath: path.pathString)
    }

    public func filesAndDirectoriesContained(in path: AbsolutePath) -> [AbsolutePath]? {
        fileManager.subpaths(atPath: path.pathString)?.map { path.appending(RelativePath($0)) }
    }

    // MARK: - MD5

    public func urlSafeBase64MD5(path: AbsolutePath) throws -> String {
        let data = try Data(contentsOf: path.url)
        let digestData = Data(Insecure.MD5.hash(data: data))
        return digestData.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }

    // MARK: - File Attributes

    public func fileSize(path: AbsolutePath) throws -> UInt64 {
        let attr = try fileManager.attributesOfItem(atPath: path.pathString)
        guard let size = attr[FileAttributeKey.size] as? UInt64 else { throw FileHandlerError.unreachableFileSize(path) }
        return size
    }

    // MARK: - Extension

    public func changeExtension(path: AbsolutePath, to fileExtension: String) throws -> AbsolutePath {
        guard isFolder(path) == false else { throw FileHandlerError.expectedAFile(path) }
        let sanitizedExtension = fileExtension.starts(with: ".") ? String(fileExtension.dropFirst()) : fileExtension
        guard path.extension != sanitizedExtension else { return path }

        let newPath = path.removingLastComponent().appending(component: "\(path.basenameWithoutExt).\(sanitizedExtension)")
        try move(from: path, to: newPath)
        return newPath
    }

    public func zipItem(at sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        try fileManager.zipItem(at: sourcePath.asURL, to: destinationPath.asURL, shouldKeepParent: false)
    }

    public func unzipItem(at sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        try fileManager.unzipItem(at: sourcePath.asURL, to: destinationPath.asURL)
    }
}
