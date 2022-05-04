import Foundation
import TSCBasic

/// An interface to archive files in a zip file.
public protocol FileArchiving {
    /// Zips files and outputs them in a zip file with the given name.
    /// - Parameter name: Name of the output zip file.
    func zip(name: String) throws -> AbsolutePath

    /// Call this method to delete the temporary directory where the .zip file has been generated.
    func delete() throws
}

public class FileArchiver: FileArchiving {
    /// Paths to be archived.
    private let paths: [AbsolutePath]

    /// Temporary directory in which the .zip file will be generated.
    private var temporaryDirectory: AbsolutePath

    /// Initializes the archiver with a list of files to archive.
    /// - Parameter paths: Paths to archive
    public init(paths: [AbsolutePath]) throws {
        self.paths = paths
        temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: false).path
    }

    public func zip(name: String) throws -> AbsolutePath {
        let destinationZipPath = temporaryDirectory.appending(component: "\(name).zip")
        // ZIPFoundation does not support zipping array of items, we instead copy them all to a single directory
        let pathsPath = temporaryDirectory.appending(component: "\(name)-paths")
        try FileHandler.shared.createFolder(pathsPath)
        try paths.forEach {
            try FileHandler.shared.copy(from: $0, to: pathsPath.appending(component: $0.basename))
        }
        try FileHandler.shared.zipItem(at: pathsPath, to: destinationZipPath)
        return destinationZipPath
    }

    public func delete() throws {
        try FileHandler.shared.delete(temporaryDirectory)
    }
}
