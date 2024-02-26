import Foundation

// A group of settings configurations.

public typealias BuildConfigurationDictionary = [ProjectAutomation.BuildConfiguration: ProjectAutomation.Configuration?]

public struct Settings: Equatable, Codable {
    public var configurations: BuildConfigurationDictionary

    public init(
        configurations: ProjectAutomation.BuildConfigurationDictionary
    ) {
        self.configurations = configurations
    }
}
