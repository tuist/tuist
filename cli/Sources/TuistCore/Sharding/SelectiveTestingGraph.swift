import Foundation

/// Pre-computed selective testing graph that is persisted during the shard plan phase
/// and restored during the shard execute phase to avoid regenerating
/// the project and rehashing targets.
public struct SelectiveTestingGraph: Codable {
    /// For each test target, the full set of (targetName, hash) pairs
    /// including transitive dependencies that should be stored on success.
    public struct TargetHashClosure: Codable {
        /// All target names and their hashes in the dependency closure
        public let hashes: [String: String]
        /// Target names that already have cache items and should be skipped when storing
        public let cachedTargetNames: Set<String>

        public init(hashes: [String: String], cachedTargetNames: Set<String>) {
            self.hashes = hashes
            self.cachedTargetNames = cachedTargetNames
        }
    }

    /// Test target name → pre-computed dependency hash closure
    public let targetHashClosures: [String: TargetHashClosure]

    /// Selective testing cache items for analytics (target name → CacheItem)
    public let selectiveTestingCacheItems: [String: CacheItem]

    public init(
        targetHashClosures: [String: TargetHashClosure],
        selectiveTestingCacheItems: [String: CacheItem]
    ) {
        self.targetHashClosures = targetHashClosures
        self.selectiveTestingCacheItems = selectiveTestingCacheItems
    }

    public static let fileName = "selective-testing-graph.json"
}
