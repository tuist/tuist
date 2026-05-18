import FileSystem
import Foundation
import Mockable
import Path
import TuistLogging

/// An interface to archive files in a zip file.
@Mockable
public protocol FileArchiving {
    /// Zips files and outputs them in a zip file with the given name.
    /// - Parameter name: Name of the output zip file.
    func zip(name: String) async throws -> AbsolutePath

    /// Call this method to delete the temporary directory where the .zip file has been generated.
    func delete() async throws
}

public class FileArchiver: FileArchiving {
    /// Paths to be archived.
    private let paths: [AbsolutePath]

    private let fileSystem: FileSysteming

    /// Temporary directory in which the .zip file will be generated.
    private var temporaryDirectory: AbsolutePath

    /// Initializes the archiver with a list of files to archive.
    /// - Parameter paths: Paths to archive
    public init(paths: [AbsolutePath], fileSystem: FileSysteming = FileSystem()) throws {
        self.paths = paths
        self.fileSystem = fileSystem
        temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: false).path
    }

    public func zip(name: String) async throws -> AbsolutePath {
        let destinationZipPath = temporaryDirectory.appending(component: "\(name).zip")
        // ZIPFoundation does not support zipping array of items, we instead copy them all to a single directory.
        let pathsDirectoryPath = temporaryDirectory.appending(component: "\(name)-paths")
        try await fileSystem.makeDirectory(at: pathsDirectoryPath)

        Logger.current.debug(
            "Archiving \(paths.count) path(s) into \(name).zip (staging at \(pathsDirectoryPath.pathString))"
        )

        let copyStart = Date()
        for path in paths {
            try await fileSystem.copy(path, to: pathsDirectoryPath.appending(component: path.basename))
        }
        let copyElapsed = Date().timeIntervalSince(copyStart)
        Logger.current.debug("Staging copy for \(name).zip finished in \(String(format: "%.2fs", copyElapsed))")

        let zipStart = Date()
        try await fileSystem.zipFileOrDirectoryContent(at: pathsDirectoryPath, to: destinationZipPath)
        let zipElapsed = Date().timeIntervalSince(zipStart)
        let zipBytes = (try? await fileSystem.fileMetadata(at: destinationZipPath)?.size) ?? 0
        Logger.current.debug(
            "Zipped \(name).zip in \(String(format: "%.2fs", zipElapsed)) (output: \(zipBytes) bytes)"
        )

        return destinationZipPath
    }

    public func delete() async throws {
        try await fileSystem.remove(temporaryDirectory)
    }
}
