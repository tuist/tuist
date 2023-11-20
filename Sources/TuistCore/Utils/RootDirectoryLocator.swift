import Foundation
import TSCBasic
import TuistSupport

public protocol RootDirectoryLocating {
    /// RootDirectoryLocating initializer
    /// - Parameter usingProjectManifest: value indicating if Project.swift manifest should be considered as root
    init(usingProjectManifest: Bool)
    /// Given a path, it finds the root directory by traversing up the hierarchy.
    ///
    /// A root directory is defined as (in order of precedence):
    ///   - Directory containing a `Project.swift` manifest (if `usingProjectManifest` is `true`.
    ///   - Directory containing a `Workspace.swift` manifest.
    ///   - Directory containing a `Tuist/` subdirectory.
    ///   - Directory containing a `Plugin.swift` manifest.
    ///   - Directory containing a `.git/` subdirectory.
    ///
    func locate(from path: AbsolutePath) -> AbsolutePath?
}

extension RootDirectoryLocating {
    public init() {
        self.init(usingProjectManifest: false)
    }
}

public final class RootDirectoryLocator: RootDirectoryLocating {
    private let fileHandler: FileHandling = FileHandler.shared
    internal var gitHandler: GitHandling = GitHandler()
    /// This cache avoids having to traverse the directories hierarchy every time the locate method is called.
    @Atomic private var cache: [AbsolutePath: AbsolutePath] = [:]
    private let usingProjectManifest: Bool

    public init(usingProjectManifest: Bool) {
        self.usingProjectManifest = usingProjectManifest
    }

    public func locate(from path: AbsolutePath) -> AbsolutePath? {
        locate(from: path, source: path)
    }

    private func locate(from path: AbsolutePath, source: AbsolutePath) -> AbsolutePath? {
        if let cachedDirectory = cached(path: path) {
            return cachedDirectory
        } else if let gitRoot = try? gitHandler.locateTopLevel(from: path) {
            return gitRoot
        } else if (usingProjectManifest && fileHandler.exists(path.appending(component: "Project.swift"))) ||
            fileHandler.exists(path.appending(component: "Workspace.swift")) ||
            fileHandler.exists(path.appending(component: Constants.tuistDirectoryName)) ||
            fileHandler.exists(path.appending(component: "Plugin.swift")) ||
            fileHandler.isFolder(path.appending(component: ".git"))
        {
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
