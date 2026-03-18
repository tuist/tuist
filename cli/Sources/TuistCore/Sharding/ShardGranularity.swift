import Foundation

public enum ShardGranularity: String, CaseIterable, Equatable, Sendable {
    case module
    case suite
}
