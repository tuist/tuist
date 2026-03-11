import Foundation

public enum ShardGranularity: String, CaseIterable, Equatable, Sendable {
    case module
    case suite
}

public struct ShardConfiguration: Equatable, Sendable {
    public let shardMin: Int?
    public let shardMax: Int?
    public let shardTotal: Int?
    public let shardMaxDuration: Int?
    public let granularity: ShardGranularity

    public init(
        shardMin: Int? = nil,
        shardMax: Int? = nil,
        shardTotal: Int? = nil,
        shardMaxDuration: Int? = nil,
        granularity: ShardGranularity = .module
    ) {
        self.shardMin = shardMin
        self.shardMax = shardMax
        self.shardTotal = shardTotal
        self.shardMaxDuration = shardMaxDuration
        self.granularity = granularity
    }
}

#if DEBUG
    extension ShardConfiguration {
        public static func test(
            shardMin: Int? = nil,
            shardMax: Int? = 3,
            shardTotal: Int? = nil,
            shardMaxDuration: Int? = nil,
            granularity: ShardGranularity = .module
        ) -> ShardConfiguration {
            ShardConfiguration(
                shardMin: shardMin,
                shardMax: shardMax,
                shardTotal: shardTotal,
                shardMaxDuration: shardMaxDuration,
                granularity: granularity
            )
        }
    }
#endif
