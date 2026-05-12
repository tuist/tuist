import Foundation
import Path
import XcodeGraph

/// Run metadata captured during the build phase (`tuist test --build-only`) and
/// restored during the test execution phase (`tuist test --without-building`)
/// when the two run as separate processes, typically across CI machines via a
/// shared `.xctestproducts` bundle.
///
/// Persisting this lets the test phase upload the same module-cache,
/// selective-testing, and build-run analytics that the build phase produced,
/// so the resulting test run page links back to the build run and surfaces
/// the cache tabs even when the actual `xcodebuild` invocation runs no tests.
public struct RunMetadata: Codable {
    public let graph: Graph?
    public let binaryCacheItems: [AbsolutePath: [String: CacheItem]]
    public let selectiveTestingCacheItems: [AbsolutePath: [String: CacheItem]]
    public let targetContentHashSubhashes: [String: TargetContentHashSubhashes]
    public let buildRunId: String?

    public init(
        graph: Graph?,
        binaryCacheItems: [AbsolutePath: [String: CacheItem]],
        selectiveTestingCacheItems: [AbsolutePath: [String: CacheItem]],
        targetContentHashSubhashes: [String: TargetContentHashSubhashes],
        buildRunId: String?
    ) {
        self.graph = graph
        self.binaryCacheItems = binaryCacheItems
        self.selectiveTestingCacheItems = selectiveTestingCacheItems
        self.targetContentHashSubhashes = targetContentHashSubhashes
        self.buildRunId = buildRunId
    }

    public static let fileName = "run-metadata.json"
}
