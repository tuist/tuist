import FileSystem
import Foundation
import Mockable
import Path
import ZIPFoundation

@Mockable
public protocol FileUnarchiving {
    /// Unarchives the files into a temporary directory and returns the path to that directory.
    func unzip() async throws -> AbsolutePath

    /// Call this method to delete the temporary directory where the .zip file has been generated.
    func delete() async throws
}

public class FileUnarchiver: FileUnarchiving {
    /// Path to the .zip file to unarchive
    private let path: AbsolutePath

    /// Temporary directory in which the .zip file will be generated.
    private var temporaryDirectory: AbsolutePath

    private let fileSystem: FileSystem

    /// Initializes the unarchiver with the path to the file to unarchive.
    /// - Parameter path: Path to the .zip file to unarchive.
    public init(path: AbsolutePath, fileSystem: FileSystem = FileSystem()) throws {
        self.path = path
        self.fileSystem = fileSystem
        temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: false).path
    }

    public func unzip() async throws -> AbsolutePath {
        try await fileSystem.unzip(path, to: temporaryDirectory)
        return temporaryDirectory
    }

    /// Extracts a distribution whose links may cross sibling directories but must resolve inside the archive.
    public func unzipSelfContained() async throws -> AbsolutePath {
        let archive = try Archive(url: path.url, accessMode: .read)
        let root = try AbsolutePath(validating: temporaryDirectory.url.resolvingSymlinksInPath().path)
        func validate(_ path: AbsolutePath) throws {
            let resolved = try AbsolutePath(validating: path.url.resolvingSymlinksInPath().path)
            guard resolved.isDescendantOfOrEqual(to: root) else { throw Archive.ArchiveError.uncontainedSymlink }
        }
        // Extract files before links so no archive entry can write through a link.
        let entries = archive.sorted { $0.type != .symlink && $1.type == .symlink }
        let links = try entries.filter { $0.type == .symlink }.map {
            temporaryDirectory.appending(try RelativePath(validating: $0.path))
        }
        for entry in entries {
            try Task.checkCancellation()
            let destination = temporaryDirectory.appending(try RelativePath(validating: entry.path))
            guard links.allSatisfy({ !destination.isDescendant(of: $0) }) else {
                throw Archive.ArchiveError.uncontainedSymlink
            }
            try validate(destination)
            let checksum = try archive.extract(entry, to: destination.url, allowUncontainedSymlinks: true)
            guard checksum == entry.checksum else { throw Archive.ArchiveError.invalidCRC32 }
        }
        // Validate actual links after all targets exist, including chained links and parent traversals.
        for link in links {
            guard FileManager.default.fileExists(atPath: link.pathString) else {
                throw Archive.ArchiveError.uncontainedSymlink
            }
            try validate(link)
        }
        return temporaryDirectory
    }

    public func delete() async throws {
        try await fileSystem.remove(temporaryDirectory)
    }
}
