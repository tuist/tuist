import Foundation
import TuistCore
import TuistGraph
@testable import TuistCache

public final class MockCacheGraphContentHasher: CacheGraphContentHashing {
    public init() {}

    public var contentHashesStub: (
        (Graph, TuistGraph.Cache.Profile, CacheOutputType, Set<String>) throws
            -> [GraphTarget: String]
    )?
    public func contentHashes(
        for graph: Graph,
        cacheProfile: TuistGraph.Cache.Profile,
        cacheOutputType: CacheOutputType,
        excludedTargets: Set<String>
    ) throws -> [GraphTarget: String] {
        try contentHashesStub?(graph, cacheProfile, cacheOutputType, excludedTargets) ?? [:]
    }
}
