extension Tuist {
    public struct InstallOptions: Codable, Equatable, Sendable {
        public var passthroughSwiftPackageManagerArguments: [String]

        public init(
            passthroughSwiftPackageManagerArguments: [String] = []
        ) {
            self.passthroughSwiftPackageManagerArguments = passthroughSwiftPackageManagerArguments
        }
    }
}
