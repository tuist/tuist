import Foundation
import TSCBasic

final class FileHandler {
    private let fileManager: FileManager = .default

    var currentPath: AbsolutePath {
        AbsolutePath(fileManager.currentDirectoryPath)
    }

    func copy(path: AbsolutePath, to: AbsolutePath) throws {
        try fileManager.copyItem(atPath: path.pathString, toPath: to.pathString)
    }

    func exists(path: AbsolutePath) -> Bool {
        fileManager.fileExists(atPath: path.pathString)
    }

    func contents(of path: AbsolutePath) throws -> Data {
        try Data(contentsOf: path.asURL)
    }
}
