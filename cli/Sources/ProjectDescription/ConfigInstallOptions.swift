extension Config {
    /// Options for install.
    public struct InstallOptions: Codable, Equatable, Sendable {
        /// Arguments passed to the Swift Package Manager's `swift package` command when running `swift package resolve`.
        public var passthroughSwiftPackageManagerArguments: [String]

        /// Controls which process environment variables dependency manifests can observe during installation.
        public var packageManifestEnvironment: ManifestEnvironment

        public static func options(
            passthroughSwiftPackageManagerArguments: [String] = [],
            packageManifestEnvironment: ManifestEnvironment = .automatic
        ) -> Self {
            self.init(
                passthroughSwiftPackageManagerArguments: passthroughSwiftPackageManagerArguments,
                packageManifestEnvironment: packageManifestEnvironment
            )
        }

        /// Controls which environment variables are visible to dependency manifests and participate in their cache keys.
        public struct ManifestEnvironment: Codable, Equatable, Sendable {
            /// Whether to exclude volatile values that Tuist recognizes from supported continuous-integration providers.
            public let usesAutomaticProviderDefaults: Bool

            /// Patterns for variables that remain visible, even when an automatic provider default would exclude them.
            public let includedVariablePatterns: [String]

            /// Patterns for additional variables to hide from dependency manifests and their cache keys.
            public let excludedVariablePatterns: [String]

            private init(
                usesAutomaticProviderDefaults: Bool,
                includedVariablePatterns: [String] = [],
                excludedVariablePatterns: [String] = []
            ) {
                self.usesAutomaticProviderDefaults = usesAutomaticProviderDefaults
                self.includedVariablePatterns = includedVariablePatterns
                self.excludedVariablePatterns = excludedVariablePatterns
            }

            /// Uses provider-specific defaults to hide volatile continuous-integration values.
            public static let automatic = Self(usesAutomaticProviderDefaults: true)

            /// Preserves the complete process environment.
            public static let all = Self(usesAutomaticProviderDefaults: false)

            /// Uses provider-specific defaults, optionally restoring or excluding additional variables.
            ///
            /// Entries can be literal names (for example, `CI_JOB_ID`) or names ending in `*` for prefix matching
            /// (for example, `GITHUB_RUN_*`). Included entries take precedence over automatic and custom exclusions.
            public static func automatic(
                including includedVariablePatterns: [String] = [],
                excluding excludedVariablePatterns: [String] = []
            ) -> Self {
                Self(
                    usesAutomaticProviderDefaults: true,
                    includedVariablePatterns: includedVariablePatterns,
                    excludedVariablePatterns: excludedVariablePatterns
                )
            }
        }
    }
}
