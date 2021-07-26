import Foundation
import RxSwift
import TSCBasic
import TuistCache
import TuistCore
import TuistGraph
import TuistSupportTesting

public final class MockCacheArtifactBuilder: CacheArtifactBuilding {
    public init() {}

    public var invokedCacheOutputTypeGetter = false
    public var invokedCacheOutputTypeGetterCount = 0
    public var stubbedCacheOutputType: CacheOutputType!

    public var cacheOutputType: CacheOutputType {
        invokedCacheOutputTypeGetter = true
        invokedCacheOutputTypeGetterCount += 1
        return stubbedCacheOutputType
    }

    public var invokedBuildProjectTarget = false
    public var invokedBuildProjectTargetCount = 0
    // swiftlint:disable:next large_tuple
    public var invokedBuildProjectTargetParameters: (projectTarget: XcodeBuildTarget, target: Target, outputDirectory: AbsolutePath)?
    public var invokedBuildProjectTargetParametersList = [(projectTarget: XcodeBuildTarget, target: Target, outputDirectory: AbsolutePath)]()
    public var stubbedBuildProjectTargetError: Error?
    public func build(projectTarget: XcodeBuildTarget, target: Target, configuration _: String, into outputDirectory: AbsolutePath) throws {
        invokedBuildProjectTarget = true
        invokedBuildProjectTargetCount += 1
        invokedBuildProjectTargetParameters = (projectTarget, target, outputDirectory)
        invokedBuildProjectTargetParametersList.append((projectTarget, target, outputDirectory))
        if let error = stubbedBuildProjectTargetError {
            throw error
        }
    }
}
