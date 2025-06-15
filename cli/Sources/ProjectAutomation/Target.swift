import Foundation

/// The structure defining the output schema of a target.
public struct Target: Codable, Equatable, Sendable {
    /// The name of the target.
    public let name: String

    /// The product type the target produces.
    public let product: String

    /// The bundleId of the target.
    public let bundleId: String

    /// List of file paths that are the target's sources.
    public let sources: [String]

    /// List of file paths that are the target's resources.
    public let resources: [String]

    /// The target’s settings.
    public let settings: Settings

    /// The target’s dependencies.
    public let dependencies: [TargetDependency]

    public init(
        name: String,
        product: String,
        bundleId: String,
        sources: [String],
        resources: [String],
        settings: Settings,
        dependencies: [TargetDependency]
    ) {
        self.name = name
        self.product = product
        self.bundleId = bundleId
        self.sources = sources
        self.resources = resources
        self.settings = settings
        self.dependencies = dependencies
    }
}
