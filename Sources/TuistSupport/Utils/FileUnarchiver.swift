import FileSystem
import Foundation
import Mockable
import Path

@Mockable
public protocol FileUnarchiving {
    /// Unarchives the files into a temporary directory and returns the path to that directory.
    func unzip() throws -> AbsolutePath

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

    public func unzip() throws -> AbsolutePath {
        try FileHandler.shared.unzipItem(at: path, to: temporaryDirectory)
        return temporaryDirectory
    }

    public func delete() async throws {
        try await fileSystem.remove(temporaryDirectory)
    }
}
