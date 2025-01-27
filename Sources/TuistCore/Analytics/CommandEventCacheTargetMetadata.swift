import Foundation

public struct CommandEventCacheTargetMetadata: Codable, Hashable {
    public let hash: String
    public let hit: CommandEventCacheHit

    public init(
        hash: String,
        hit: CommandEventCacheHit
    ) {
        self.hash = hash
        self.hit = hit
    }
}
