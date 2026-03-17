import Foundation

public struct ShardAssignment: Equatable, Sendable {
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

public struct ShardPlan: Equatable, Sendable {
    public let sessionId: String
    public let shardCount: Int
    public let shards: [ShardAssignment]
    public let uploadId: String

    public init(
        sessionId: String,
        shardCount: Int,
        shards: [ShardAssignment],
        uploadId: String
    ) {
        self.sessionId = sessionId
        self.shardCount = shardCount
        self.shards = shards
        self.uploadId = uploadId
    }
}

#if DEBUG
    extension ShardAssignment {
        public static func test(
            index: Int = 0,
            testTargets: [String] = ["AppTests"],
            estimatedDurationMs: Int = 100
        ) -> ShardAssignment {
            ShardAssignment(
                index: index,
                testTargets: testTargets,
                estimatedDurationMs: estimatedDurationMs
            )
        }
    }

    extension ShardPlan {
        public static func test(
            sessionId: String = "test-session-1",
            shardCount: Int = 2,
            shards: [ShardAssignment] = [
                .test(index: 0, testTargets: ["AppTests"]),
                .test(index: 1, testTargets: ["CoreTests"]),
            ],
            uploadId: String = "upload-id-123"
        ) -> ShardPlan {
            ShardPlan(
                sessionId: sessionId,
                shardCount: shardCount,
                shards: shards,
                uploadId: uploadId
            )
        }
    }
#endif
