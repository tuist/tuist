import Foundation

public struct Arguments: Equatable, Codable {
    // MARK: - Attributes

    public let environmentVariables: [EnvironmentVariable]
    public let launchArguments: [LaunchArgument]

    // MARK: - Init

    public init(environmentVariables: [EnvironmentVariable] = [],
                launchArguments: [LaunchArgument] = [])
    {
        self.environmentVariables = environmentVariables
        self.launchArguments = launchArguments
    }
}
