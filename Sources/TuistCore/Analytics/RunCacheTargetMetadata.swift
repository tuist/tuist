import Foundation

public struct RunCacheTargetMetadata: Codable, Hashable {
    public let hash: String
    public let hit: RunCacheHit

    public init(
        hash: String,
        hit: RunCacheHit
    ) {
        self.hash = hash
        self.hit = hit
    }
}
