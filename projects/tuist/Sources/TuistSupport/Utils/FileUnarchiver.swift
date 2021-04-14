import Foundation
import TSCBasic
import Zip

/// An interface to unarchive files from a zip file.
public protocol FileUnarchiving {
    /// Unarchives the files into a temporary directory and returns the path to that directory.
    func unzip() throws -> AbsolutePath

    /// Call this method to delete the temporary directory where the .zip file has been generated.
    func delete() throws
}

public class FileUnarchiver: FileUnarchiving {
    /// Path to the .zip file to unarchive
    private let path: AbsolutePath

    /// Temporary directory in which the .zip file will be generated.
    private var temporaryDirectory: AbsolutePath

    /// Initializes the unarchiver with the path to the file to unarchive.
    /// - Parameter path: Path to the .zip file to unarchive.
    public init(path: AbsolutePath) throws {
        self.path = path
        temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: false).path
    }

    public func unzip() throws -> AbsolutePath {
        try Zip.unzipFile(path.url, destination: temporaryDirectory.url, overwrite: true, password: nil)
        return temporaryDirectory
    }

    public func delete() throws {
        try FileHandler.shared.delete(temporaryDirectory)
    }
}
