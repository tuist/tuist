import Foundation
import TuistCore
import TuistGraph
@testable import TuistCache

public final class MockCacheGraphContentHasher: CacheGraphContentHashing {
    public init() {}

    public var contentHashesStub: ((Graph, TuistGraph.Cache.Profile, CacheOutputType) throws -> [TargetNode: String])?
    public func contentHashes(
        for graph: Graph,
        cacheProfile: TuistGraph.Cache.Profile,
        cacheOutputType: CacheOutputType
    ) throws -> [TargetNode: String] {
        try contentHashesStub?(graph, cacheProfile, cacheOutputType) ?? [:]
    }
}
