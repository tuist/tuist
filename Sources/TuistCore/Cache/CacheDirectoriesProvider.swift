import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

public protocol CacheDirectoriesProviding {
    /// Returns the cache directory for a Tuist cache category
    func tuistCacheDirectory(for category: CacheCategory) throws -> AbsolutePath

    func cacheDirectory() throws -> AbsolutePath
}

public final class CacheDirectoriesProvider: CacheDirectoriesProviding {
    private let fileHandler: FileHandling

    init(fileHandler: FileHandling) {
        self.fileHandler = fileHandler
    }

    public convenience init() {
        self.init(fileHandler: FileHandler.shared)
    }

    public func tuistCacheDirectory(for category: CacheCategory) throws -> AbsolutePath {
        return CacheDirectoriesProvider.tuistCacheDirectory(for: category, cacheDirectory: try cacheDirectory())
    }

    public static func tuistCacheDirectory(for category: CacheCategory, cacheDirectory: AbsolutePath) -> AbsolutePath {
        return cacheDirectory.appending(components: ["tuist", category.directoryName])
    }

    public func cacheDirectory() throws -> TSCBasic.AbsolutePath {
        if let xdgCacheHome = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"] {
            return try AbsolutePath(validating: xdgCacheHome)
        } else {
            return FileHandler.shared.homeDirectory.appending(components: ".cache")
        }
    }
}
