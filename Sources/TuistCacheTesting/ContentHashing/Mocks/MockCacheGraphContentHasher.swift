import Foundation
import TuistCore
import TuistGraph
@testable import TuistCache

public final class MockCacheGraphContentHasher: CacheGraphContentHashing {
    public init() {}

    public var contentHashesStub: ((Graph, TuistGraph.Cache.Profile, CacheOutputType) throws -> [GraphTarget: String])?
    public func contentHashes(
        for graph: Graph,
        cacheProfile: TuistGraph.Cache.Profile,
        cacheOutputType: CacheOutputType
    ) throws -> [GraphTarget: String] {
        try contentHashesStub?(graph, cacheProfile, cacheOutputType) ?? [:]
    }
}
