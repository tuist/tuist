public struct RunCacheTargetMetadata: Codable, Hashable {
    public let hash: String
    public let hit: RunCacheHit
    public let subhashes: TargetContentHashSubhashes?
    /// Whether a binary taken from the cache carries coverage counters; nil for a miss or when unknown.
    public let instrumented: Bool?

    public init(
        hash: String,
        hit: RunCacheHit,
        subhashes: TargetContentHashSubhashes? = nil,
        instrumented: Bool? = nil
    ) {
        self.hash = hash
        self.hit = hit
        self.subhashes = subhashes
        self.instrumented = instrumented
    }
}
