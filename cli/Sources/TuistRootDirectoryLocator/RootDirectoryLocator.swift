import FileSystem
import Foundation
import Mockable
import Path
import TuistCore
import TuistSupport

enum RootDirectoryLocatorError: FatalError, Equatable {
    /// Thrown when the root directory can't be located.
    case rootDirectoryNotFound(AbsolutePath)

    var type: ErrorType {
        switch self {
        case .rootDirectoryNotFound: return .abort
        }
    }

    var description: String {
        switch self {
        case let .rootDirectoryNotFound(path):
            return "Couldn't locate the root directory from path \(path.pathString). The root directory is the closest directory that contains a Tuist or a .git directory."
        }
    }
}

@Mockable
public protocol RootDirectoryLocating {
    /// Given a path, it finds the root directory by traversing up the hierarchy.
    ///
    /// A root directory is defined as (in order of precedence):
    ///   - Directory containing a `Tuist/` subdirectory.
    ///   - Directory containing a `Plugin.swift` manifest.
    ///   - Directory containing a `.git/` subdirectory.
    ///
    func locate(from path: AbsolutePath) async throws -> AbsolutePath?
}

extension RootDirectoryLocating {
    public func locate(from path: AbsolutePath) async throws -> AbsolutePath {
        guard let rootDirectory = try await locate(from: path)
        else { throw RootDirectoryLocatorError.rootDirectoryNotFound(path) }
        return rootDirectory
    }
}

public final class RootDirectoryLocator: RootDirectoryLocating {
    private let fileSystem: FileSysteming
    /// This cache avoids having to traverse the directories hierarchy every time the locate method is called.
    private let cache: ThreadSafe<[AbsolutePath: AbsolutePath]> = ThreadSafe([:])

    public init(
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.fileSystem = fileSystem
    }

    public func locate(from path: AbsolutePath) async throws -> AbsolutePath? {
        if let path = try await locate(from: path, source: path) {
            return path
        } else if try await fileSystem.exists(path, isDirectory: true), try await fileSystem.exists(
            path.appending(component: Constants.SwiftPackageManager.packageSwiftName),
            isDirectory: false
        ) {
            return path
        }

        return nil
    }

    private func locate(from path: AbsolutePath, source: AbsolutePath) async throws -> AbsolutePath? {
        if try await !fileSystem.exists(path, isDirectory: true) {
            return try await locate(from: path.parentDirectory, source: source)
        } else if let cachedDirectory = cached(path: path) {
            return cachedDirectory
        } else if try await fileSystem.exists(path.appending(component: Constants.tuistDirectoryName), isDirectory: true) {
            cache(rootDirectory: path, for: source)
            return path
        } else if try await fileSystem.exists(path.appending(component: Constants.tuistManifestFileName), isDirectory: false) {
            cache(rootDirectory: path, for: source)
            return path
        } else if try await fileSystem.exists(path.appending(component: "Plugin.swift")) {
            cache(rootDirectory: path, for: source)
            return path
        } else if try await fileSystem.exists(path.appending(component: ".git"), isDirectory: true) {
            cache(rootDirectory: path, for: source)
            return path
        } else if !path.isRoot {
            return try await locate(from: path.parentDirectory, source: source)
        }
        return nil
    }

    // MARK: - Fileprivate

    fileprivate func cached(path: AbsolutePath) -> AbsolutePath? {
        cache.value[path]
    }

    /// This method caches the root directory of path, and all its parents up to the root directory.
    /// - Parameters:
    ///   - rootDirectory: Path to the root directory.
    ///   - path: Path for which we are caching the root directory.
    fileprivate func cache(rootDirectory: AbsolutePath, for path: AbsolutePath) {
        if path != rootDirectory {
            cache.mutate { $0[path] = rootDirectory }
            cache(rootDirectory: rootDirectory, for: path.parentDirectory)
        } else if path == rootDirectory {
            cache.mutate { $0[path] = rootDirectory }
        }
    }
}
