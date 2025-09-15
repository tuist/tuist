extension Tuist {
    /// Options for caching.
    public struct CacheOptions: Codable, Equatable, Sendable {
        public var keepSourceTargets: Bool

        public static func options(
            keepSourceTargets: Bool = false
        ) -> Self {
            self.init(
                keepSourceTargets: keepSourceTargets
            )
        }
    }
}
