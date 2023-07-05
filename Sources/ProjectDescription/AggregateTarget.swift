import Foundation

/// An aggregate target of a project.
public struct AggregateTarget: Codable, Equatable {
    /// The name of the target.
    public let name: String

    /// The build phase scripts actions for the target.
    public let scripts: [TargetScript]

    /// The target's settings.
    public let settings: Settings?

    public init(
        name: String,
        scripts: [TargetScript] = [],
        settings: Settings? = nil
    ) {
        self.name = name
        self.settings = settings
        self.scripts = scripts
    }
}
