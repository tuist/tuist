import Foundation
import TSCBasic
import Zip

protocol FileArchiving {
    func zip(xcframeworkPath: AbsolutePath) throws -> AbsolutePath
}

class FileArchiver: FileArchiving {
    func zip(xcframeworkPath: AbsolutePath) throws -> AbsolutePath {
        let destinationZipPath = xcframeworkPath.removingLastComponent().appending(component: "\(xcframeworkPath.basenameWithoutExt).zip")
        try Zip.zipFiles(paths: [xcframeworkPath.url], zipFilePath: destinationZipPath.url, password: nil, progress: nil)
        return destinationZipPath
    }
}
