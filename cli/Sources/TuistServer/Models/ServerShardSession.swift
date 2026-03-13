import Foundation

public struct ServerShardAssignment: Equatable, Sendable {
    public let index: Int
    public let testTargets: [String]
    public let estimatedDurationMs: Int

    public init(
        index: Int,
        testTargets: [String],
        estimatedDurationMs: Int
    ) {
        self.index = index
        self.testTargets = testTargets
        self.estimatedDurationMs = estimatedDurationMs
    }
}

public struct ServerShardSession: Equatable, Sendable {
    public let sessionId: String
    public let shardCount: Int
    public let shards: [ServerShardAssignment]
    public let uploadId: String

    public init(
        sessionId: String,
        shardCount: Int,
        shards: [ServerShardAssignment],
        uploadId: String
    ) {
        self.sessionId = sessionId
        self.shardCount = shardCount
        self.shards = shards
        self.uploadId = uploadId
    }
}
