import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

public protocol CacheDirectoriesProviding {
    /// Returns the cache directory for a cache category
    func cacheDirectory(for category: CacheCategory) -> AbsolutePath
}

public final class CacheDirectoriesProvider: CacheDirectoriesProviding {
    public init() {}

    public func cacheDirectory(for category: CacheCategory) -> AbsolutePath {
        let directory: AbsolutePath
        if let xdgCacheHome = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"] {
            directory = (try! AbsolutePath(validating: xdgCacheHome)).appending(component: "tuist")
        } else {
            directory = FileHandler.shared.homeDirectory.appending(components: ".cache", "tuist")
        }
        return directory.appending(component: category.directoryName)
    }
}
