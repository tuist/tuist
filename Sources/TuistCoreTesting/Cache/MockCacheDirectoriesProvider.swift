import Foundation
import TSCBasic
import TuistSupport
@testable import TuistCore

public final class MockCacheDirectoriesProvider: CacheDirectoriesProviding {
    private let directory: TemporaryDirectory
    public var cacheDirectoryStub: AbsolutePath?
    public var currentDirectoryStub: AbsolutePath?

    private var cacheDirectory: AbsolutePath {
        cacheDirectoryStub ?? directory.path.appending(component: "Cache")
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
            return cacheDirectory.appending(RelativePath("Tuist/Dependencies"))
        }
    }

    public init() throws {
        directory = try TemporaryDirectory(removeTreeOnDeinit: true)
    }
}
