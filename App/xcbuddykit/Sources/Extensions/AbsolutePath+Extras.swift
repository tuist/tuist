import Foundation
import Basic

extension AbsolutePath {
    static var current: AbsolutePath {
        return AbsolutePath(FileManager.default.currentDirectoryPath)
    }
}
