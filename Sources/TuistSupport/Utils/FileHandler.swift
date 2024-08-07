import CryptoKit
import Foundation
import Path
import TSCBasic
import ZIPFoundation

public enum FileHandlerError: FatalError, Equatable {
    case invalidTextEncoding(Path.AbsolutePath)
    case writingError(Path.AbsolutePath)
    case fileNotFound(Path.AbsolutePath)
    case unreachableFileSize(Path.AbsolutePath)
    case expectedAFile(Path.AbsolutePath)
    case propertyListDecodeError(Path.AbsolutePath, description: String)

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
        case let .propertyListDecodeError(path, description):
            return "The property list file at path \(path.pathString) is invalid and cannot be decoded:\n\(description)"
        }
    }

    public var type: ErrorType {
        switch self {
        case .invalidTextEncoding:
            return .bug
        case .writingError, .fileNotFound, .unreachableFileSize, .expectedAFile, .propertyListDecodeError:
            return .abort
        }
    }
}

/// Protocol that defines the interface of an object that provides convenient
/// methods to interact with the system files and folders.
public protocol FileHandling: AnyObject {
    /// Returns the current path.
    var currentPath: Path.AbsolutePath { get }

    /// Returns `AbsolutePath` to home directory
    var homeDirectory: Path.AbsolutePath { get }

    func replace(_ to: Path.AbsolutePath, with: Path.AbsolutePath) throws
    func exists(_ path: Path.AbsolutePath) -> Bool
    func move(from: Path.AbsolutePath, to: Path.AbsolutePath) throws
    func copy(from: Path.AbsolutePath, to: Path.AbsolutePath) throws
    func readFile(_ at: Path.AbsolutePath) throws -> Data
    func readTextFile(_ at: Path.AbsolutePath) throws -> String
    func readPlistFile<T: Decodable>(_ at: Path.AbsolutePath) throws -> T
    /// Determine temporary directory either default for user or specified by ENV variable
    func determineTemporaryDirectory() throws -> Path.AbsolutePath
    func temporaryDirectory() throws -> Path.AbsolutePath
    func inTemporaryDirectory(_ closure: @escaping (Path.AbsolutePath) async throws -> Void) async throws
    func inTemporaryDirectory(_ closure: (Path.AbsolutePath) throws -> Void) throws
    func inTemporaryDirectory(removeOnCompletion: Bool, _ closure: (Path.AbsolutePath) throws -> Void) throws
    func inTemporaryDirectory<Result>(_ closure: (Path.AbsolutePath) throws -> Result) throws -> Result
    func inTemporaryDirectory<Result>(removeOnCompletion: Bool, _ closure: (Path.AbsolutePath) throws -> Result) throws -> Result
    func write(_ content: String, path: Path.AbsolutePath, atomically: Bool) throws
    func locateDirectoryTraversingParents(from: Path.AbsolutePath, path: String) -> Path.AbsolutePath?
    func locateDirectory(_ path: String, traversingFrom from: Path.AbsolutePath) throws -> Path.AbsolutePath?
    func files(
        in path: Path.AbsolutePath,
        filter: ((URL) -> Bool)?,
        nameFilter: Set<String>?,
        extensionFilter: Set<String>?
    ) -> Set<Path.AbsolutePath>
    func files(
        in path: Path.AbsolutePath,
        nameFilter: Set<String>?,
        extensionFilter: Set<String>?
    ) -> Set<Path.AbsolutePath>
    func glob(_ path: Path.AbsolutePath, glob: String) -> [Path.AbsolutePath]
    func throwingGlob(_ path: Path.AbsolutePath, glob: String) throws -> [Path.AbsolutePath]
    func linkFile(atPath: Path.AbsolutePath, toPath: Path.AbsolutePath) throws
    func createFolder(_ path: Path.AbsolutePath) throws
    func isFolder(_ path: Path.AbsolutePath) -> Bool
    func touch(_ path: Path.AbsolutePath) throws
    func contentsOfDirectory(_ path: Path.AbsolutePath) throws -> [Path.AbsolutePath]
    func urlSafeBase64MD5(path: Path.AbsolutePath) throws -> String
    func fileSize(path: Path.AbsolutePath) throws -> UInt64
    func changeExtension(path: Path.AbsolutePath, to newExtension: String) throws -> Path.AbsolutePath
    func resolveSymlinks(_ path: Path.AbsolutePath) throws -> Path.AbsolutePath
    func fileAttributes(at path: Path.AbsolutePath) throws -> [FileAttributeKey: Any]
    func filesAndDirectoriesContained(in path: Path.AbsolutePath) throws -> [Path.AbsolutePath]?
    func zipItem(at sourcePath: Path.AbsolutePath, to destinationPath: Path.AbsolutePath) throws
    func unzipItem(at sourcePath: Path.AbsolutePath, to destinationPath: Path.AbsolutePath) throws
}

extension FileHandling {
    public func files(
        in path: Path.AbsolutePath,
        nameFilter: Set<String>?,
        extensionFilter: Set<String>?
    ) -> Set<Path.AbsolutePath> {
        files(in: path, filter: nil, nameFilter: nameFilter, extensionFilter: extensionFilter)
    }
}

public class FileHandler: FileHandling {
    // MARK: - Attributes

    public static var shared: FileHandling {
        _shared.value
    }

    // swiftlint:disable:next identifier_name
    static let _shared: ThreadSafe<FileHandling> = ThreadSafe(FileHandler())

    private let fileManager: FileManager
    private let propertyListDecoder = PropertyListDecoder()

    /// Initializes the file handler with its attributes.
    ///
    /// - Parameter fileManager: File manager instance.
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public var currentPath: Path.AbsolutePath {
        try! AbsolutePath(validating: fileManager.currentDirectoryPath) // swiftlint:disable:this force_try
    }

    public var homeDirectory: Path.AbsolutePath {
        try! AbsolutePath(validating: NSHomeDirectory()) // swiftlint:disable:this force_try
    }

    public func replace(_ to: Path.AbsolutePath, with: Path.AbsolutePath) throws {
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

    public func temporaryDirectory() throws -> Path.AbsolutePath {
        let directory = try TemporaryDirectory(removeTreeOnDeinit: false)
        return directory.path
    }

    public func determineTemporaryDirectory() throws -> Path.AbsolutePath {
        try .init(validating: determineTempDirectory().pathString)
    }

    public func inTemporaryDirectory<Result>(_ closure: (Path.AbsolutePath) throws -> Result) throws -> Result {
        try withTemporaryDirectory(removeTreeOnDeinit: true) { path in
            try closure(.init(validating: path.pathString))
        }
    }

    public func inTemporaryDirectory(removeOnCompletion: Bool, _ closure: (Path.AbsolutePath) throws -> Void) throws {
        try withTemporaryDirectory(removeTreeOnDeinit: removeOnCompletion) { path in
            try closure(.init(validating: path.pathString))
        }
    }

    public func inTemporaryDirectory(_ closure: (Path.AbsolutePath) throws -> Void) throws {
        try withTemporaryDirectory(removeTreeOnDeinit: true) { path in
            try closure(.init(validating: path.pathString))
        }
    }

    public func inTemporaryDirectory(_ closure: @escaping (Path.AbsolutePath) async throws -> Void) async throws {
        let directory = try TemporaryDirectory(removeTreeOnDeinit: true)
        try await closure(directory.path)
    }

    public func inTemporaryDirectory<Result>(
        removeOnCompletion: Bool,
        _ closure: (Path.AbsolutePath) throws -> Result
    ) throws -> Result {
        try withTemporaryDirectory(removeTreeOnDeinit: removeOnCompletion) { path in
            try closure(try .init(validating: path.pathString))
        }
    }

    public func exists(_ path: Path.AbsolutePath) -> Bool {
        let exists = fileManager.fileExists(atPath: path.pathString)
        return exists
    }

    public func copy(from: Path.AbsolutePath, to: Path.AbsolutePath) throws {
        try fileManager.copyItem(atPath: from.pathString, toPath: to.pathString)
    }

    public func move(from: Path.AbsolutePath, to: Path.AbsolutePath) throws {
        try fileManager.moveItem(atPath: from.pathString, toPath: to.pathString)
    }

    public func readFile(_ at: Path.AbsolutePath) throws -> Data {
        return try Data(contentsOf: at.url)
    }

    public func readTextFile(_ at: Path.AbsolutePath) throws -> String {
        let data = try Data(contentsOf: at.url)
        if let content = String(data: data, encoding: .utf8) {
            return content
        } else {
            throw FileHandlerError.invalidTextEncoding(at)
        }
    }

    public func readPlistFile<T: Decodable>(_ at: Path.AbsolutePath) throws -> T {
        guard let data = fileManager.contents(atPath: at.pathString) else {
            throw FileHandlerError.fileNotFound(at)
        }
        do {
            return try propertyListDecoder.decode(T.self, from: data)
        } catch {
            if let debugDescription = (error as NSError).userInfo["NSDebugDescription"] as? String {
                throw FileHandlerError.propertyListDecodeError(at, description: debugDescription)
            } else {
                throw FileHandlerError.propertyListDecodeError(at, description: error.localizedDescription)
            }
        }
    }

    public func linkFile(atPath: Path.AbsolutePath, toPath: Path.AbsolutePath) throws {
        try fileManager.linkItem(atPath: atPath.pathString, toPath: toPath.pathString)
    }

    public func write(_ content: String, path: Path.AbsolutePath, atomically: Bool) throws {
        do {
            try content.write(to: path.url, atomically: atomically, encoding: .utf8)
        } catch {}
    }

    public func locateDirectory(_ path: String, traversingFrom from: Path.AbsolutePath) throws -> Path.AbsolutePath? {
        let extendedPath = from.appending(try RelativePath(validating: path))
        if exists(extendedPath) {
            return extendedPath
        } else if !from.isRoot {
            return try locateDirectory(path, traversingFrom: from.parentDirectory)
        } else {
            return nil
        }
    }

    public func files(
        in path: Path.AbsolutePath,
        filter: ((URL) -> Bool)?,
        nameFilter: Set<String>?,
        extensionFilter: Set<String>?
    ) -> Set<Path.AbsolutePath> {
        var results = Set<Path.AbsolutePath>()

        let enumerator = fileManager.enumerator(
            at: path.url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        func filterCandidate(with url: URL) -> Bool {
            if let extensionFilter {
                guard extensionFilter.contains(url.pathExtension) else {
                    return false
                }
            }
            if let nameFilter {
                guard nameFilter.contains(url.lastPathComponent) else {
                    return false
                }
            }
            if let filter {
                guard filter(url) else {
                    return false
                }
            }
            return true
        }

        while let candidateURL = enumerator?.nextObject() as? Foundation.URL {
            guard filterCandidate(with: candidateURL) else {
                continue
            }
            // Symlinks need to be resolved for resulting absolute URLs to point to the right place.
            let url = candidateURL.resolvingSymlinksInPath()
            let absolutePath = AbsolutePath(stringLiteral: url.path)
            results.insert(absolutePath)
        }

        return results
    }

    public func glob(_ path: Path.AbsolutePath, glob: String) -> [Path.AbsolutePath] {
        path.glob(glob)
    }

    public func throwingGlob(_ path: Path.AbsolutePath, glob: String) throws -> [Path.AbsolutePath] {
        try path.throwingGlob(glob)
    }

    public func createFolder(_ path: Path.AbsolutePath) throws {
        try fileManager.createDirectory(
            at: path.url,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    public func touch(_ path: Path.AbsolutePath) throws {
        try fileManager.createDirectory(
            at: path.removingLastComponent().url,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try Data().write(to: path.url)
    }

    public func isFolder(_ path: Path.AbsolutePath) -> Bool {
        var isDirectory = ObjCBool(true)
        let exists = fileManager.fileExists(atPath: path.pathString, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    public func locateDirectoryTraversingParents(from: Path.AbsolutePath, path: String) -> Path.AbsolutePath? {
        let configPath = from.appending(component: path)

        let root = try! Path.AbsolutePath(validating: "/") // swiftlint:disable:this force_try
        if FileHandler.shared.exists(configPath) {
            return configPath
        } else if from == root {
            return nil
        } else {
            return locateDirectoryTraversingParents(from: from.parentDirectory, path: path)
        }
    }

    public func contentsOfDirectory(_ path: Path.AbsolutePath) throws -> [Path.AbsolutePath] {
        try fileManager.contentsOfDirectory(atPath: path.pathString).map { try AbsolutePath(validating: $0, relativeTo: path) }
    }

    public func createSymbolicLink(at path: Path.AbsolutePath, destination: Path.AbsolutePath) throws {
        try fileManager.createSymbolicLink(atPath: path.pathString, withDestinationPath: destination.pathString)
    }

    public func resolveSymlinks(_ path: Path.AbsolutePath) throws -> Path.AbsolutePath {
        try .init(validating: TSCBasic.resolveSymlinks(.init(validating: path.pathString)).pathString)
    }

    public func fileAttributes(at path: Path.AbsolutePath) throws -> [FileAttributeKey: Any] {
        try fileManager.attributesOfItem(atPath: path.pathString)
    }

    public func filesAndDirectoriesContained(in path: Path.AbsolutePath) throws -> [Path.AbsolutePath]? {
        try fileManager.subpaths(atPath: path.pathString)?.map { path.appending(try RelativePath(validating: $0)) }
    }

    // MARK: - MD5

    public func urlSafeBase64MD5(path: Path.AbsolutePath) throws -> String {
        let data = try Data(contentsOf: path.url)
        let digestData = Data(Insecure.MD5.hash(data: data))
        return digestData.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }

    // MARK: - File Attributes

    public func fileSize(path: Path.AbsolutePath) throws -> UInt64 {
        let attr = try fileManager.attributesOfItem(atPath: path.pathString)
        guard let size = attr[FileAttributeKey.size] as? UInt64 else { throw FileHandlerError.unreachableFileSize(path) }
        return size
    }

    // MARK: - Extension

    public func changeExtension(path: Path.AbsolutePath, to fileExtension: String) throws -> Path.AbsolutePath {
        guard isFolder(path) == false else { throw FileHandlerError.expectedAFile(path) }
        let sanitizedExtension = fileExtension.starts(with: ".") ? String(fileExtension.dropFirst()) : fileExtension
        guard path.extension != sanitizedExtension else { return path }

        let newPath = path.removingLastComponent().appending(component: "\(path.basenameWithoutExt).\(sanitizedExtension)")
        try move(from: path, to: newPath)
        return newPath
    }

    public func zipItem(at sourcePath: Path.AbsolutePath, to destinationPath: Path.AbsolutePath) throws {
        try fileManager.zipItem(
            at: URL(fileURLWithPath: sourcePath.pathString),
            to: URL(fileURLWithPath: destinationPath.pathString),
            shouldKeepParent: false
        )
    }

    public func unzipItem(at sourcePath: Path.AbsolutePath, to destinationPath: Path.AbsolutePath) throws {
        try fileManager.unzipItem(
            at: URL(fileURLWithPath: sourcePath.pathString),
            to: URL(fileURLWithPath: destinationPath.pathString)
        )
    }
}
