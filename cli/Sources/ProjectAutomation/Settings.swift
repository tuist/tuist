import Foundation

// A group of settings configurations.

public struct Settings: Equatable, Codable, Sendable {
    public var configurations: [ProjectAutomation.BuildConfiguration: ProjectAutomation.Configuration?]

    public init(
        configurations: [ProjectAutomation.BuildConfiguration: ProjectAutomation.Configuration?]
    ) {
        self.configurations = configurations
    }
}
