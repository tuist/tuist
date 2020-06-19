import Foundation
import TSCBasic
import Zip

protocol FileArchiving {
    func zip(xcframeworkPath: AbsolutePath, hash: String) throws -> AbsolutePath
}

class FileArchiver: FileArchiving {
    func zip(xcframeworkPath: AbsolutePath, hash: String) throws -> AbsolutePath {
        let destinationZipPath = xcframeworkPath.removingLastComponent().appending(component: "\(hash).zip")
        try Zip.zipFiles(paths: [xcframeworkPath.url], zipFilePath: destinationZipPath.url, password: nil, progress: nil)
        return destinationZipPath
    }
}
