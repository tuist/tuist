import Foundation
import Mockable
import TuistCore
import XcodeGraph

@Mockable
public protocol SelectiveTestingServicing {
    /// - Returns: Tests that are cached.
    func cachedTests(
        scheme: Scheme,
        graph: Graph,
        selectiveTestingHashes: [GraphTarget: String],
        selectiveTestingCacheItems: [CacheItem]
    ) async throws -> [TestIdentifier]
}
