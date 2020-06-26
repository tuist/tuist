import Foundation
import TSCBasic
import Zip

public protocol FileArchiving {
    func zip() throws -> AbsolutePath
    func delete() throws
}

public class FileArchiver: FileArchiving {
    private let path: AbsolutePath
    private var temporaryDirectory: TemporaryDirectory!

    init(path: AbsolutePath) {
        self.path = path
    }

    public func zip() throws -> AbsolutePath {
        temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: false)
        let destinationZipPath = temporaryDirectory.path.appending(component: "\(path.basenameWithoutExt).zip")
        try Zip.zipFiles(paths: [path.url], zipFilePath: destinationZipPath.url, password: nil, progress: nil)
        return destinationZipPath
    }

    public func delete() throws {
        try FileHandler.shared.delete(temporaryDirectory.path)
    }
}
