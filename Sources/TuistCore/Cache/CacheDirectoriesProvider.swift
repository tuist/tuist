import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

public protocol CacheDirectoriesProviding {
    /// Returns the cache directory for a cache category
    func cacheDirectory(for category: CacheCategory) -> AbsolutePath
}

public final class CacheDirectoriesProvider: CacheDirectoriesProviding {
    public let cacheDirectory: AbsolutePath
    // swiftlint:disable:next force_try
    private static let defaultDirectory = try! AbsolutePath(validating: URL(fileURLWithPath: NSHomeDirectory()).path)
        .appending(component: ".tuist")
    private static var forcedCacheDirectory: AbsolutePath? {
        ProcessInfo.processInfo.environment[Constants.EnvironmentVariables.forceConfigCacheDirectory]
            .map { try! AbsolutePath(validating: $0) } // swiftlint:disable:this force_try
    }

    public init(config: Config?) {
        if let cacheDirectory = config?.cache?.path {
            self.cacheDirectory = cacheDirectory
        } else {
            cacheDirectory = CacheDirectoriesProvider.defaultDirectory.appending(component: "Cache")
        }
    }

    public func cacheDirectory(for category: CacheCategory) -> AbsolutePath {
        (Self.forcedCacheDirectory ?? cacheDirectory).appending(component: category.directoryName)
    }
}

extension CacheCategory {
    var directoryName: String {
        switch self {
        case .plugins:
            return "Plugins"
        case .builds:
            return "BuildCache"
        case .tests:
            return "TestsCache"
        case .generatedAutomationProjects:
            return "Projects"
        case .projectDescriptionHelpers:
            return "ProjectDescriptionHelpers"
        case .manifests:
            return "Manifests"
        }
    }
}
