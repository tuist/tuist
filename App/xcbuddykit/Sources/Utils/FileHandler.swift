import Basic
import Foundation

protocol FileHandling: AnyObject {
    var currentPath: AbsolutePath { get }
    func exists(_ path: AbsolutePath) -> Bool
    func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath]
}

final class FileHandler: FileHandling {
    var currentPath: AbsolutePath {
        return AbsolutePath(FileManager.default.currentDirectoryPath)
    }

    func exists(_ path: AbsolutePath) -> Bool {
        return FileManager.default.fileExists(atPath: path.asString)
    }

    func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath] {
        return path.glob(glob)
    }
}
