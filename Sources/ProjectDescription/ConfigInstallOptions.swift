extension Config {
    /// Options for install.
    public struct InstallOptions: Codable, Equatable, Sendable {
        /// Arguments passed to Swift Package Manager.
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
