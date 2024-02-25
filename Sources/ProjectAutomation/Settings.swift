import Foundation

// A group of settings configurations.

public typealias BuildConfigurationDictionary = Dictionary<ProjectAutomation.BuildConfiguration, ProjectAutomation.Configuration>

public struct Settings: Equatable, Codable {
    /// A dictionary with build settings that are inherited from all the configurations.
    public var configurations: [String]

    public init(
        configurations: BuildConfigurationDictionary
    ) {
        self.configurations = configurations.keys.map { buildConfiguration in
            buildConfiguration.name
        }.sorted()
    }
}
