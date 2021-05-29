import Foundation
import TuistCore
import TuistGraph
@testable import TuistCache

public final class MockCacheGraphContentHasher: CacheGraphContentHashing {
    public init() {}

    public var contentHashesStub: ((ValueGraph, TuistGraph.Cache.Profile, CacheOutputType) throws -> [ValueGraphTarget: String])?
    public func contentHashes(
        for graph: ValueGraph,
        cacheProfile: TuistGraph.Cache.Profile,
        cacheOutputType: CacheOutputType
    ) throws -> [ValueGraphTarget: String] {
        try contentHashesStub?(graph, cacheProfile, cacheOutputType) ?? [:]
    }
}
