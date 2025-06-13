import Foundation

public struct RunCacheTargetMetadata: Codable, Hashable {
    public let hash: String
    public let hit: RunCacheHit
    public let buildDuration: TimeInterval?

    public init(
        hash: String,
        hit: RunCacheHit,
        buildDuration: TimeInterval? = nil
    ) {
        self.hash = hash
        self.hit = hit
        self.buildDuration = buildDuration
    }
}
