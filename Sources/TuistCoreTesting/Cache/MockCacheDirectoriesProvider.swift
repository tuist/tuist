import Foundation
import TSCBasic
import TuistSupport
@testable import TuistCore

public final class MockCacheDirectoriesProvider: CacheDirectoriesProviding {
    private let directory: TemporaryDirectory
    public var cacheDirectoryStub: AbsolutePath?

    public var cacheDirectory: AbsolutePath {
        cacheDirectoryStub ?? directory.path.appending(component: "Cache")
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

    public init() throws {
        directory = try TemporaryDirectory(removeTreeOnDeinit: true)
    }
}
