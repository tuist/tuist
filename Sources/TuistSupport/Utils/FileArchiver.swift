import Foundation
import Mockable
import TSCBasic

/// An interface to archive files in a zip file.
@Mockable
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
        /// ZIPFoundation does not support zipping array of items, we instead copy them all to a single directory
        let pathsDirectoryPath = temporaryDirectory.appending(component: "\(name)-paths")
        try FileHandler.shared.createFolder(pathsDirectoryPath)
        for path in paths {
            try FileHandler.shared.copy(from: path, to: pathsDirectoryPath.appending(component: path.basename))
        }
        try FileHandler.shared.zipItem(at: pathsDirectoryPath, to: destinationZipPath)
        return destinationZipPath
    }

    public func delete() throws {
        try FileHandler.shared.delete(temporaryDirectory)
    }
}
