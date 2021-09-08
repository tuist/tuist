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
    private static let defaultDirectory = AbsolutePath(URL(fileURLWithPath: NSHomeDirectory()).path).appending(component: ".tuist")

    public init(config: Config?) {
        if let cacheDirectory = config?.cache?.path {
            self.cacheDirectory = cacheDirectory
        } else {
            cacheDirectory = CacheDirectoriesProvider.defaultDirectory.appending(component: "Cache")
        }
    }

    public func cacheDirectory(for category: CacheCategory) -> AbsolutePath {
        switch category {
        case .plugins:
            return cacheDirectory.appending(component: "Plugins")
        case .builds:
            return cacheDirectory.appending(component: "BuildCache")
        case .tests:
            return cacheDirectory.appending(component: "TestsCache")
        case .generatedAutomationProjects:
            return cacheDirectory.appending(component: "Projects")
        case .projectDescriptionHelpers:
            return cacheDirectory.appending(component: "ProjectDescriptionHelpers")
        case .manifests:
            return cacheDirectory.appending(component: "Manifests")
        case .dependencies:
            return FileHandler.shared.currentPath.appending(RelativePath("Tuist/Dependencies"))
        }
    }
}
