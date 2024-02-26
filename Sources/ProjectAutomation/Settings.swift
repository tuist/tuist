import Foundation

// A group of settings configurations.

public typealias BuildConfigurationDictionary = [ProjectAutomation.BuildConfiguration: ProjectAutomation.Configuration]

public struct Settings: Equatable, Codable {
    public var configurations: [ProjectAutomation.Configuration]

    public init(
        configurations: ProjectAutomation.BuildConfigurationDictionary
    ) {
        self.configurations = configurations.map { _, configuration in
            ProjectAutomation.Configuration(
                name: configuration.name,
                variant: configuration.variant
            )
        }.sorted()
    }
}
