import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

public protocol CacheDirectoriesProviding {
    /// Returns all the cache directories
    var cacheDirectories: [AbsolutePath] { get }

    /// Returns the directory where the plugin are cached.
    var pluginCacheDirectory: AbsolutePath { get }

    /// Returns the directory where the build artifacts are cached.
    var buildCacheDirectory: AbsolutePath { get }

    /// Returns the directory where hashes of modules that have been a part of successful test are cached
    var testsCacheDirectory: AbsolutePath { get }

    /// Returns the directory where the projects generated for automation tasks are generated to
    var generatedAutomationProjectsDirectory: AbsolutePath { get }

    /// Returns the directory where the project description helper modules are cached.
    var projectDescriptionHelpersCacheDirectory: AbsolutePath { get }

    /// Returns the directory where the project description helper modules are cached.
    var manifestCacheDirectory: AbsolutePath { get }
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

    public var pluginCacheDirectory: AbsolutePath {
        cacheDirectory.appending(component: "Plugins")
    }

    public var testsCacheDirectory: AbsolutePath {
        cacheDirectory.appending(component: "TestsCache")
    }

    public var buildCacheDirectory: AbsolutePath {
        cacheDirectory.appending(component: "BuildCache")
    }

    public var generatedAutomationProjectsDirectory: AbsolutePath {
        cacheDirectory.appending(component: "Projects")
    }

    public var projectDescriptionHelpersCacheDirectory: AbsolutePath {
        cacheDirectory.appending(component: "ProjectDescriptionHelpers")
    }

    public var manifestCacheDirectory: AbsolutePath {
        cacheDirectory.appending(component: "Manifests")
    }

    public var cacheDirectories: [AbsolutePath] {
        [
            cacheDirectory,
            pluginCacheDirectory,
            buildCacheDirectory,
            testsCacheDirectory,
            generatedAutomationProjectsDirectory,
            projectDescriptionHelpersCacheDirectory,
            manifestCacheDirectory,
        ]
    }
}
