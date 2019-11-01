import Basic
import Foundation
import TuistSupport

protocol RootDirectoryLocating {
    /// Given a path, it finds the root directory by traversing up the hierarchy.
    /// The root directory is considered the directory that contains a Tuist/ directory or the directory where the
    /// git repository is defined if no Tuist/ directory is found.
    /// - Parameter path: Path for which we'll look the root directory.
    func locate(from path: AbsolutePath) -> AbsolutePath?
}

final class RootDirectoryLocator: RootDirectoryLocating {
    /// This cache avoids having to traverse the directories hierarchy every time the locate method is called.
    fileprivate var cache: [AbsolutePath: AbsolutePath] = [:]

    /// Given a path, it finds the root directory by traversing up the hierarchy.
    /// The root directory is considered the directory that contains a Tuist/ directory or the directory where the
    /// git repository is defined if no Tuist/ directory is found.
    /// - Parameter path: Path for which we'll look the root directory.
    func locate(from path: AbsolutePath) -> AbsolutePath? {
        if let cachedDirectory = self.cache[path] {
            return cachedDirectory
        } else if let tuistDirectory = FileHandler.shared.locateDirectoryTraversingParents(from: path, Constants.tuistFolderName) {
            let rootDirectory = tuistDirectory.parentDirectory
            cache(rootDirectory: rootDirectory, for: path)
            return rootDirectory
        } else if let gitDirectory = FileHandler.shared.locateDirectoryTraversingParents(from: path, ".git") {
            let rootDirectory = gitDirectory.parentDirectory
            cache(rootDirectory: rootDirectory, for: path)
            return rootDirectory
        } else {
            return nil
        }
    }

    // MARK: - Fileprivate

    /// This method caches the root directory of path, and all its parents up to the root directory.
    /// - Parameters:
    ///   - rootDirectory: Path to the root directory.
    ///   - path: Path for which we are caching the root directory.
    fileprivate func cache(rootDirectory: AbsolutePath, for path: AbsolutePath) {
        if path != rootDirectory {
            cache[path] = rootDirectory
            cache(rootDirectory: rootDirectory, for: path.parentDirectory)
        } else if path == rootDirectory {
            cache[path] = rootDirectory
        }
    }
}
