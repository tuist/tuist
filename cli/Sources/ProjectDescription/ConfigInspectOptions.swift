extension Config {
    /// Options for inspect.
    public struct InspectOptions: Codable, Equatable, Sendable {
        /// Options for inspect redundant dependencies.
        public struct RedundantDependencies: Codable, Equatable, Sendable {
            /// The set of tags which targets should be ignored when inspecting redundant dependencies
            public let ignoreTagsMatching: Set<String>

            public static func redundantDependencies(
                ignoreTagsMatching: Set<String> = []
            ) -> Self {
                self.init(
                    ignoreTagsMatching: ignoreTagsMatching
                )
            }
        }

        /// Options for inspect redundant dependencies.
        public var redundantDependencies: RedundantDependencies

        public static func options(
            redundantDependencies: RedundantDependencies = .redundantDependencies()
        ) -> Self {
            self.init(
                redundantDependencies: redundantDependencies
            )
        }
    }
}
