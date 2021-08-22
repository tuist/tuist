import Foundation

public struct Arguments: Equatable, Codable {
    public let environmentVariables: [EnvironmentVariable]
    public let launchArguments: [LaunchArgument]

    @available(*, deprecated, message: "Use init with `launchArguments: [LaunchArgument]` instead")
    public init(environmentVariables: [EnvironmentVariable] = [],
                launchArguments: [String: Bool])
    {
        self.environmentVariables = environmentVariables
        self.launchArguments = launchArguments.map(LaunchArgument.init)
            .sorted { $0.name < $1.name }
    }

    public init(environmentVariables: [EnvironmentVariable] = [],
                launchArguments: [LaunchArgument] = [])
    {
        self.environmentVariables = environmentVariables
        self.launchArguments = launchArguments
    }
}
