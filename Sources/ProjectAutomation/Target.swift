import Foundation

/// The structure defining the output schema of a target.
public struct Target: Codable, Equatable {
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
    public let settings: ProjectAutomation.Settings

    /// The target’s dependencies.
    public let dependencies: [ProjectAutomation.TargetDependency]

    public init(
        name: String,
        product: String,
        bundleId: String,
        sources: [String],
        resources: [String],
        settings: ProjectAutomation.Settings,
        dependencies: [ProjectAutomation.TargetDependency]
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
