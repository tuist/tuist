import Foundation
import TSCBasic
import Zip

public protocol FileArchiving {
    func zip() throws -> AbsolutePath
    func unzip(to: AbsolutePath) throws
    func delete() throws
}

public class FileArchiver: FileArchiving {
    private let path: AbsolutePath
    private var temporaryArtefact: AbsolutePath!

    init(path: AbsolutePath) {
        self.path = path
    }

    public func zip() throws -> AbsolutePath {
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: false)
        temporaryArtefact = temporaryDirectory.path
        let destinationZipPath = temporaryDirectory.path.appending(component: "\(path.basenameWithoutExt).zip")
        try Zip.zipFiles(paths: [path.url], zipFilePath: destinationZipPath.url, password: nil, progress: nil)
        return destinationZipPath
    }

    public func unzip(to: AbsolutePath) throws {
        temporaryArtefact = path
        try Zip.unzipFile(path.url, destination: to.url, overwrite: true, password: nil)
    }

    public func delete() throws {
        try FileHandler.shared.delete(temporaryArtefact)
    }
}
