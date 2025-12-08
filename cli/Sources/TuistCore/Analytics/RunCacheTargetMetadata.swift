import Foundation

public struct RunCacheTargetMetadata: Codable, Hashable {
    public let hash: String
    public let hit: RunCacheHit
    public let buildDuration: TimeInterval?
    public let subhashes: TargetContentHashSubhashes?

    public init(
        hash: String,
        hit: RunCacheHit,
        buildDuration: TimeInterval? = nil,
        subhashes: TargetContentHashSubhashes? = nil
    ) {
        self.hash = hash
        self.hit = hit
        self.buildDuration = buildDuration
        self.subhashes = subhashes
    }
}
