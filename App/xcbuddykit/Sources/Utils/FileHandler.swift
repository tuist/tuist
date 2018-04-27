import Basic
import Foundation

/// Protocol that represents an object that can handle files.
protocol FileHandling: AnyObject {
    /// Returns the current path.
    var currentPath: AbsolutePath { get }

    /// Returns whether a given path points to an existing file.
    ///
    /// - Parameter path: path to check.
    /// - Returns: true if there's a file at the given path.
    func exists(_ path: AbsolutePath) -> Bool

    /// Returns all the files using the glob pattern.
    ///
    /// - Parameters:
    ///   - path: base path.
    ///   - glob: glob pattern.
    /// - Returns: list of paths that have been found matching the glob pattern.
    func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath]
}

/// Default file handler implementing FileHandling.
final class FileHandler: FileHandling {
    /// Returns the current path.
    var currentPath: AbsolutePath {
        return AbsolutePath(FileManager.default.currentDirectoryPath)
    }

    /// Returns whether a given path points to an existing file.
    ///
    /// - Parameter path: path to check.
    /// - Returns: true if there's a file at the given path.
    func exists(_ path: AbsolutePath) -> Bool {
        return FileManager.default.fileExists(atPath: path.asString)
    }

    /// Returns all the files using the glob pattern.
    ///
    /// - Parameters:
    ///   - path: base path.
    ///   - glob: glob pattern.
    /// - Returns: list of paths that have been found matching the glob pattern.
    func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath] {
        return path.glob(glob)
    }
}
