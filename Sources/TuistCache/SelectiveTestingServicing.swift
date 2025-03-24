import Foundation
import Mockable
import TuistCore
import XcodeGraph

@Mockable
public protocol SelectiveTestingServicing {
    /// - Returns: Tests that are cached.
    func cachedTests(
        testableGraphTargets: [GraphTarget],
        selectiveTestingHashes: [GraphTarget: String],
        selectiveTestingCacheItems: [CacheItem]
    ) async throws -> [TestIdentifier]
}
