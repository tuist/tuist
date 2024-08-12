extension Config {
    /// Options for install.
    public struct InstallOptions: Codable, Equatable, Sendable {
        /// Arguments passed to the Swift Package Manager's `swift package` command when running `swift package resolve`.
        public var passthroughSwiftPackageManagerArguments: [String]

        public static func options(
            passthroughSwiftPackageManagerArguments: [String] = []
        ) -> Self {
            self.init(
                passthroughSwiftPackageManagerArguments: passthroughSwiftPackageManagerArguments
            )
        }
    }
}
