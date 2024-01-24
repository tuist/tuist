import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

public protocol CacheDirectoriesProviding {
    /// Returns the cache directory for a cache category
    func cacheDirectory(for category: CacheCategory) -> AbsolutePath
}

public final class CacheDirectoriesProvider: CacheDirectoriesProviding {
    // swiftlint:disable:next force_try
    private static let defaultDirectory = try! AbsolutePath(validating: URL(fileURLWithPath: NSHomeDirectory()).path)
        .appending(component: ".tuist")
    private static var forcedCacheDirectory: AbsolutePath? {
        ProcessInfo.processInfo.environment[Constants.EnvironmentVariables.forceConfigCacheDirectory]
            .map { try! AbsolutePath(validating: $0) } // swiftlint:disable:this force_try
    }

    public init() {}

    public func cacheDirectory(for category: CacheCategory) -> AbsolutePath {
        let cacheDirectory = CacheDirectoriesProvider.defaultDirectory.appending(component: "Cache")
        return (Self.forcedCacheDirectory ?? cacheDirectory).appending(component: category.directoryName)
    }
}
