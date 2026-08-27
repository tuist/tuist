extension Config {
    /// Options for install.
    public struct InstallOptions: Codable, Equatable, Sendable {
        /// Arguments passed to the Swift Package Manager's `swift package` command when running `swift package resolve`.
        public var passthroughSwiftPackageManagerArguments: [String]

        /// Names of process environment variables that Tuist excludes from dependency-manifest evaluation and cache keys.
        ///
        /// Each entry is either a literal name (for example, `CI_JOB_ID`) or a name ending in `*` for prefix matching
        /// (for example, `GITHUB_RUN_*`). Excluding a variable makes it unavailable to every `Package.swift` evaluated
        /// during `tuist install`, so only exclude variables that do not affect dependency declarations.
        public var manifestEnvironmentExcluded: [String]

        public static func options(
            passthroughSwiftPackageManagerArguments: [String] = [],
            manifestEnvironmentExcluded: [String] = []
        ) -> Self {
            self.init(
                passthroughSwiftPackageManagerArguments: passthroughSwiftPackageManagerArguments,
                manifestEnvironmentExcluded: manifestEnvironmentExcluded
            )
        }
    }
}
