public struct PackageTraitSelection: Codable, Equatable, Sendable {
    public let package: Package
    public let traits: [String]

    public init(package: Package, traits: [String]) {
        self.package = package
        self.traits = traits
    }
}
