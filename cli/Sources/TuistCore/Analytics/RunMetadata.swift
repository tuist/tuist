import Foundation
import Path
import XcodeGraph

/// Run metadata captured during the build phase (`tuist test --build-only`) and
/// restored during the test execution phase (`tuist test --without-building`)
/// when the two run as separate processes, typically across CI machines via a
/// shared `.xctestproducts` bundle.
///
/// Persisting this lets the test phase restore the graph and selective-testing
/// state, and link back to the original build run. Binary cache results remain in
/// the snapshot for compatibility, but are not restored as new cache lookups.
public struct RunMetadata: Codable {
    public let graph: Graph?
    public let binaryCacheItems: [AbsolutePath: [String: CacheItem]]
    public let selectiveTestingCacheItems: [AbsolutePath: [String: CacheItem]]
    public let targetContentHashSubhashes: [String: TargetContentHashSubhashes]
    public let buildRunId: String?
    /// The coverage-based test selection run the build created, for the test phase to upload with.
    public let testImpactRunId: String?
    /// The tests coverage-based test selection skipped, for an unsharded test phase: bare module
    /// names and `module/suite/name` identifiers. Sharded runs read theirs from the shard.
    public let testImpactSkip: [String]?

    public init(
        graph: Graph?,
        binaryCacheItems: [AbsolutePath: [String: CacheItem]],
        selectiveTestingCacheItems: [AbsolutePath: [String: CacheItem]],
        targetContentHashSubhashes: [String: TargetContentHashSubhashes],
        buildRunId: String?,
        testImpactRunId: String? = nil,
        testImpactSkip: [String]? = nil
    ) {
        self.graph = graph
        self.binaryCacheItems = binaryCacheItems
        self.selectiveTestingCacheItems = selectiveTestingCacheItems
        self.targetContentHashSubhashes = targetContentHashSubhashes
        self.buildRunId = buildRunId
        self.testImpactRunId = testImpactRunId
        self.testImpactSkip = testImpactSkip
    }

    public static let fileName = "run-metadata.json"
}
