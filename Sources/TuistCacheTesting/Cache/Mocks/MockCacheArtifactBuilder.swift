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

    public var invokedBuildSchemeProject = false
    public var invokedBuildSchemeProjectCount = 0
    // swiftlint:disable:next large_tuple
    public var invokedBuildSchemeProjectParameters: (scheme: Scheme, projectTarget: XcodeBuildTarget, outputDirectory: AbsolutePath)?
    public var invokedBuildchemeProjectParametersList = [(scheme: Scheme, projectTarget: XcodeBuildTarget, outputDirectory: AbsolutePath)]()
    public var stubbedBuildSchemeProjectError: Error?
    public func build(scheme: Scheme, projectTarget: XcodeBuildTarget, configuration _: String, into outputDirectory: AbsolutePath) throws {
        invokedBuildSchemeProject = true
        invokedBuildSchemeProjectCount += 1
        invokedBuildSchemeProjectParameters = (scheme, projectTarget, outputDirectory)
        invokedBuildchemeProjectParametersList.append((scheme, projectTarget, outputDirectory))
        if let error = stubbedBuildSchemeProjectError {
            throw error
        }
    }
}
