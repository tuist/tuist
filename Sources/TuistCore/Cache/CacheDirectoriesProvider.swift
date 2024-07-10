import Foundation
import Mockable
import Path
import TuistSupport
import XcodeGraph

@Mockable
public protocol CacheDirectoriesProviding {
    /// Returns the cache directory for a Tuist cache category
    func cacheDirectory(for category: CacheCategory) throws -> AbsolutePath
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

    public func cacheDirectory(for category: CacheCategory) throws -> AbsolutePath {
        try cacheDirectory().appending(components: ["tuist", category.directoryName])
    }

    public func cacheDirectory() throws -> Path.AbsolutePath {
        if let xdgCacheHome = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"] {
            return try AbsolutePath(validating: xdgCacheHome)
        } else {
            return FileHandler.shared.homeDirectory.appending(components: ".cache")
        }
    }
}
