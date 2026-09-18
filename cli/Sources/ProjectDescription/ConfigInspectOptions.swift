extension Config {
    /// Options for inspect.
    public struct InspectOptions: Codable, Equatable, Sendable {
        /// Options for inspect implicit dependencies.
        public struct ImplicitDependencies: Codable, Equatable, Sendable {
            /// Dependencies to ignore for each target when inspecting implicit dependencies.
            public let ignoreDependencies: [String: Set<String>]

            public static func implicitDependencies(
                ignoreDependencies: [String: Set<String>] = [:]
            ) -> Self {
                self.init(ignoreDependencies: ignoreDependencies)
            }
        }

        /// Options for inspect redundant dependencies.
        public struct RedundantDependencies: Codable, Equatable, Sendable {
            /// The set of tags which targets should be ignored when inspecting redundant dependencies
            public let ignoreTagsMatching: Set<String>
            /// Dependencies to ignore for each target when inspecting redundant dependencies.
            public let ignoreDependencies: [String: Set<String>]

            public static func redundantDependencies(
                ignoreTagsMatching: Set<String> = [],
                ignoreDependencies: [String: Set<String>] = [:]
            ) -> Self {
                self.init(
                    ignoreTagsMatching: ignoreTagsMatching,
                    ignoreDependencies: ignoreDependencies
                )
            }
        }

        /// Options for inspect implicit dependencies.
        public var implicitDependencies: ImplicitDependencies
        /// Options for inspect redundant dependencies.
        public var redundantDependencies: RedundantDependencies

        public static func options(
            implicitDependencies: ImplicitDependencies = .implicitDependencies(),
            redundantDependencies: RedundantDependencies = .redundantDependencies()
        ) -> Self {
            self.init(
                implicitDependencies: implicitDependencies,
                redundantDependencies: redundantDependencies
            )
        }
    }
}
