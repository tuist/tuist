import Foundation

/// Pre-computed selective testing data persisted during the shard plan phase
/// and restored during the shard execute phase to avoid regenerating
/// the project and rehashing targets.
public struct SelectiveTestingGraph: Codable {
    /// Test target name → hash (incorporates the target and all its transitive dependencies)
    public let testTargetHashes: [String: String]

    /// Selective testing cache items for analytics (target name → CacheItem)
    public let selectiveTestingCacheItems: [String: CacheItem]

    public init(
        testTargetHashes: [String: String],
        selectiveTestingCacheItems: [String: CacheItem]
    ) {
        self.testTargetHashes = testTargetHashes
        self.selectiveTestingCacheItems = selectiveTestingCacheItems
    }

    public static let fileName = "selective-testing-graph.json"
}
