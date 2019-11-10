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
    private let fileHandler: FileHandling = FileHandler.shared
    /// This cache avoids having to traverse the directories hierarchy every time the locate method is called.
    fileprivate var cache: [AbsolutePath: AbsolutePath] = [:]

    /// Given a path, it finds the root directory by traversing up the hierarchy.
    /// The root directory is considered the directory that contains a Tuist/ directory or the directory where the
    /// git repository is defined if no Tuist/ directory is found.
    /// - Parameter path: Path for which we'll look the root directory.
    func locate(from path: AbsolutePath) -> AbsolutePath? {
        return locate(from: path, source: path)
    }

    private func locate(from path: AbsolutePath, source: AbsolutePath) -> AbsolutePath? {
        if let cachedDirectory = cached(path: path) {
            return cachedDirectory
        } else if fileHandler.exists(path.appending(RelativePath(Constants.tuistFolderName))) {
            cache(rootDirectory: path, for: source)
            return path
        } else if fileHandler.exists(path.appending(RelativePath(".git"))) {
            cache(rootDirectory: path, for: source)
            return path
        } else if !path.isRoot {
            return locate(from: path.parentDirectory, source: source)
        }
        return nil
    }

    // MARK: - Fileprivate

    fileprivate func cached(path: AbsolutePath) -> AbsolutePath? {
        return cache[path]
    }

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
