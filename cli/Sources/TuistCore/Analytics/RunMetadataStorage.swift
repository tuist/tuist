import Foundation
import Path
import TuistSupport
import XcodeGraph

/// Storage for run metadata, such as binary cache.
public actor RunMetadataStorage {
    @TaskLocal public static var current: RunMetadataStorage = .init()

    public init() {}

    /// A unique ID associated with a specific run
    public var runId: String { Environment.current.processId }

    /// Graph associated with the current run
    public private(set) var graph: Graph?
    public func update(graph: Graph?) {
        self.graph = graph
    }

    /// Graph associated with the current run
    public private(set) var graphBinaryBuildDuration: TimeInterval?
    public func update(graphBinaryBuildDuration: TimeInterval?) {
        self.graphBinaryBuildDuration = graphBinaryBuildDuration
    }

    /// Binar cache-specific cache items
    public private(set) var binaryCacheItems: [AbsolutePath: [String: CacheItem]] = [:]
    public func update(binaryCacheItems: [AbsolutePath: [String: CacheItem]]) {
        self.binaryCacheItems = binaryCacheItems
    }

    /// Selective testing-specific cache items
    public private(set) var selectiveTestingCacheItems: [AbsolutePath: [String: CacheItem]] = [:]
    public func update(selectiveTestingCacheItems: [AbsolutePath: [String: CacheItem]]) {
        self.selectiveTestingCacheItems = selectiveTestingCacheItems
    }

    /// Target content hash subhashes keyed by hash
    public private(set) var targetContentHashSubhashes: [String: TargetContentHashSubhashes] = [:]
    public func update(targetContentHashSubhashes: [String: TargetContentHashSubhashes]) {
        self.targetContentHashSubhashes = targetContentHashSubhashes
    }

    /// Preview associated with the current run
    public private(set) var previewId: String?
    public func update(previewId: String?) {
        self.previewId = previewId
    }

    /// Path to the result bundle that should be uploaded when running commands like `tuist xcodebuild test`
    public private(set) var resultBundlePath: AbsolutePath?
    public func update(resultBundlePath: AbsolutePath?) {
        self.resultBundlePath = resultBundlePath
    }

    /// The ID of the latest build run.
    public private(set) var buildRunId: String?
    public func update(buildRunId: String?) {
        self.buildRunId = buildRunId
    }

    /// The ID of the latest test run.
    public private(set) var testRunId: String?
    public func update(testRunId: String?) {
        self.testRunId = testRunId
    }

    /// Cache endpoint used for the current run (regional module cache)
    public private(set) var cacheEndpoint: String = ""
    public func update(cacheEndpoint: String) {
        self.cacheEndpoint = cacheEndpoint
    }
}
