import Foundation
import TSCBasic
import Zip

public protocol FileArchiving {
    func zip() throws -> AbsolutePath
}

public protocol FileArchiverManufacturing {
    func makeFileArchiver(for path: AbsolutePath) -> FileArchiving
    func makeFileArchiver(for path: AbsolutePath, fileHandler: FileHandling) -> FileArchiving
}

public class FileArchiverFactory: FileArchiverManufacturing {
    public init() {}

    public func makeFileArchiver(for path: AbsolutePath) -> FileArchiving {
        makeFileArchiver(for: path, fileHandler: FileHandler())
    }

    public func makeFileArchiver(for path: AbsolutePath, fileHandler: FileHandling) -> FileArchiving {
        FileArchiver(path: path, fileHandler: fileHandler)
    }
}

public class FileArchiver: FileArchiving {
    let path: AbsolutePath
    let fileHandler: FileHandling
    var temporaryDirectory: TemporaryDirectory!

    init(path: AbsolutePath, fileHandler: FileHandling) {
        self.path = path
        self.fileHandler = fileHandler
    }

    public func zip() throws -> AbsolutePath {
        temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let destinationZipPath = temporaryDirectory.path.appending(component: "\(path.basenameWithoutExt).zip")
        try Zip.zipFiles(paths: [path.url], zipFilePath: destinationZipPath.url, password: nil, progress: nil)
        return destinationZipPath
    }
}
