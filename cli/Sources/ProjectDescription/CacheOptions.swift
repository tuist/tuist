extension Tuist {
    /// Options for caching.
    public struct CacheOptions: Codable, Equatable, Sendable {
        /// When true, it preserves the sources of all the targets in the graph. Note that when this option is set to true, the
        /// graph is not focused.
        public var keepSourceTargets: Bool

        /// You can use this option to limit the network concurrency at the application level. By default is is set to 15, and you
        /// can use `nil` to drop the limit.
        public var concurrencyLimit: Int?

        /// Options to configure the cache functionality.
        /// - Parameters:
        ///   - keepSourceTargets: When true, it preserves the sources of all the targets in the graph. Note that when this option
        /// is set to true, the graph is not focused.
        ///   - concurrencyLimit: You can use this option to limit the network concurrency at the application level. By default is
        /// is set to 15, and you can use `nil` to drop the limit.
        /// - Returns: Cache options.
        public static func options(
            keepSourceTargets: Bool = false,
            concurrencyLimit: Int = 15
        ) -> Self {
            self.init(
                keepSourceTargets: keepSourceTargets,
                concurrencyLimit: concurrencyLimit
            )
        }
    }
}
