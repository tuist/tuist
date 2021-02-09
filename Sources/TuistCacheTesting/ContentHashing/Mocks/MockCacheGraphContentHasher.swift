import Foundation
import TuistCore
@testable import TuistCache

public final class MockCacheGraphContentHasher: CacheGraphContentHashing {
    public init() {}

    public var contentHashesStub: ((Graph, CacheOutputType) throws -> [TargetNode: String])?
    public func contentHashes(for graph: Graph, cacheOutputType: CacheOutputType) throws -> [TargetNode: String] {
        try contentHashesStub?(graph, cacheOutputType) ?? [:]
    }
}
