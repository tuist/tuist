import Foundation
import TSCBasic
import Zip
import TuistSupport

protocol FileArchiving {
    func zip() throws -> AbsolutePath
}

protocol FileArchiverManufacturing {
    func makeFileArchiver(for path: AbsolutePath) -> FileArchiving
    func makeFileArchiver(for path: AbsolutePath, fileHandler: FileHandling) -> FileArchiving
}

class FileArchiverFactory: FileArchiverManufacturing {
    func makeFileArchiver(for path: AbsolutePath) -> FileArchiving {
        makeFileArchiver(for: path, fileHandler: FileHandler())
    }
    
    func makeFileArchiver(for path: AbsolutePath, fileHandler: FileHandling) -> FileArchiving {
        FileArchiver(path: path, fileHandler: fileHandler)
    }
}

class FileArchiver: FileArchiving {
    
    let path: AbsolutePath
    let fileHandler: FileHandling
    
    init(path: AbsolutePath, fileHandler: FileHandling) {
        self.path = path
        self.fileHandler = fileHandler
    }
    
    func zip() throws -> AbsolutePath {
        let destinationZipPath = path.removingLastComponent().appending(component: "\(path.basenameWithoutExt).zip")
        try Zip.zipFiles(paths: [path.url], zipFilePath: destinationZipPath.url, password: nil, progress: nil)
        return destinationZipPath
    }
    
    /// Remove the temporary archive file before deallocating.
    deinit {
        do {
            try fileHandler.delete(path)
        } catch {
            print("/!\\ \(#file): Could not delete archive at path \(path)")
        }
    }
}
