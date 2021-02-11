import Foundation
import TuistCore
import TuistGraph
@testable import TuistCache

public final class MockGraphContentHasher: GraphContentHashing {
    public var invokedContentHashes = false
    public var invokedContentHashesCount = 0
    public var invokedContentHashesParameters: (graph: TuistCore.Graph, cacheProfile: TuistGraph.Cache.Profile, cacheOutputType: CacheOutputType)?
    public var invokedContentHashesParametersList = [(graph: TuistCore.Graph, cacheProfile: TuistGraph.Cache.Profile, cacheOutputType: CacheOutputType)]()
    public var stubbedContentHashesError: Error?
    public var stubbedContentHashesResult: [TargetNode: String]! = [:]

    public init() {}

    public func contentHashes(for graph: TuistCore.Graph, cacheProfile: TuistGraph.Cache.Profile, cacheOutputType: CacheOutputType) throws -> [TargetNode: String] {
        invokedContentHashes = true
        invokedContentHashesCount += 1
        invokedContentHashesParameters = (graph, cacheProfile, cacheOutputType)
        invokedContentHashesParametersList.append((graph, cacheProfile, cacheOutputType))
        if let error = stubbedContentHashesError {
            throw error
        }
        return stubbedContentHashesResult
    }
}
