public struct RunCacheTargetMetadata: Codable, Hashable {
    public let hash: String
    public let hit: RunCacheHit
    public let subhashes: TargetContentHashSubhashes?

    public init(
        hash: String,
        hit: RunCacheHit,
        subhashes: TargetContentHashSubhashes? = nil
    ) {
        self.hash = hash
        self.hit = hit
        self.subhashes = subhashes
    }
}
