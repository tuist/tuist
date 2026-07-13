/// Trait selections for a native Swift package dependency.
public struct PackageTraitSelection: Codable, Equatable, Sendable {
    /// The package whose traits are selected.
    public let package: Package

    /// The selected traits. An empty array disables the package's default traits.
    public let traits: [String]

    public init(package: Package, traits: [String]) {
        self.package = package
        self.traits = traits
    }
}
