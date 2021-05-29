import Foundation
import TSCBasic
import TuistSupport

public protocol RootDirectoryLocating {
    /// Given a path, it finds the root directory by traversing up the hierarchy.
    ///
    /// A root directory is defined as (in order of precedence):
    ///   - Directory containing a `Tuist/` subdirectory.
    ///   - Directory containing a `Plugin.swift` manifest.
    ///   - Directory containing a `.git/` subdirectory.
    ///
    func locate(from path: AbsolutePath) -> AbsolutePath?
}

public final class RootDirectoryLocator: RootDirectoryLocating {
    private let fileHandler: FileHandling = FileHandler.shared
    /// This cache avoids having to traverse the directories hierarchy every time the locate method is called.
    @Atomic private var cache: [AbsolutePath: AbsolutePath] = [:]

    public init() {}

    public func locate(from path: AbsolutePath) -> AbsolutePath? {
        locate(from: path, source: path)
    }

    private func locate(from path: AbsolutePath, source: AbsolutePath) -> AbsolutePath? {
        if let cachedDirectory = cached(path: path) {
            return cachedDirectory
        } else if fileHandler.exists(path.appending(component: Constants.tuistDirectoryName)) {
            cache(rootDirectory: path, for: source)
            return path
        } else if fileHandler.exists(path.appending(component: "Plugin.swift")) {
            cache(rootDirectory: path, for: source)
            return path
        } else if fileHandler.isFolder(path.appending(component: ".git")) {
            cache(rootDirectory: path, for: source)
            return path
        } else if !path.isRoot {
            return locate(from: path.parentDirectory, source: source)
        }
        return nil
    }

    // MARK: - Fileprivate

    fileprivate func cached(path: AbsolutePath) -> AbsolutePath? {
        cache[path]
    }

    /// This method caches the root directory of path, and all its parents up to the root directory.
    /// - Parameters:
    ///   - rootDirectory: Path to the root directory.
    ///   - path: Path for which we are caching the root directory.
    fileprivate func cache(rootDirectory: AbsolutePath, for path: AbsolutePath) {
        if path != rootDirectory {
            _cache.modify { $0[path] = rootDirectory }
            cache(rootDirectory: rootDirectory, for: path.parentDirectory)
        } else if path == rootDirectory {
            _cache.modify { $0[path] = rootDirectory }
        }
    }
}
