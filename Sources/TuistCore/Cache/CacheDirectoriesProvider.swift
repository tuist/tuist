import Foundation
import Mockable
import Path
import TuistSupport
import XcodeGraph

@Mockable
public protocol CacheDirectoriesProviding {
    /// Returns the cache directory for a Tuist cache category
    func tuistCacheDirectory(for category: CacheCategory) throws -> AbsolutePath

    func tuistCloudCacheDirectory(for category: CacheCategory.App) throws -> AbsolutePath
    func tuistCloudSelectiveTestsDirectory() throws -> AbsolutePath
    func tuistCloudBinaryCacheDirectory() throws -> AbsolutePath
    func tuistCloudCacheDirectory() throws -> AbsolutePath

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

    public func cacheDirectory() throws -> Path.AbsolutePath {
        if let xdgCacheHome = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"] {
            return try AbsolutePath(validating: xdgCacheHome)
        } else {
            return FileHandler.shared.homeDirectory.appending(components: ".cache")
        }
    }

    public static func tuistCloudCacheDirectory(for category: CacheCategory.App, cacheDirectory: AbsolutePath) -> AbsolutePath {
        cacheDirectory.appending(components: ["tuist-cloud", category.directoryName])
    }

    public func tuistCloudCacheDirectory(for category: CacheCategory.App) throws -> AbsolutePath {
        switch category {
        case .binaries: return try tuistCloudBinaryCacheDirectory()
        case .selectiveTests: return try tuistCloudSelectiveTestsDirectory()
        }
    }

    public func tuistCloudSelectiveTestsDirectory() throws -> AbsolutePath {
        try tuistCloudCacheDirectory().appending(component: CacheCategory.App.selectiveTests.directoryName)
    }

    public func tuistCloudBinaryCacheDirectory() throws -> AbsolutePath {
        try tuistCloudCacheDirectory().appending(component: CacheCategory.App.binaries.directoryName)
    }

    public func tuistCloudCacheDirectory() throws -> AbsolutePath {
        try cacheDirectory().appending(components: ["tuist-cloud"])
    }
}
