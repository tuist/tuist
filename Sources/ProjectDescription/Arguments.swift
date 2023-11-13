import Foundation

/// A collection of arguments and environment variables.
public struct Arguments: Equatable, Codable {
    public let environmentVariables: [String: EnvironmentVariable]
    public let launchArguments: [LaunchArgument]

    public init(
        environmentVariables: [String: EnvironmentVariable] = [:],
        launchArguments: [LaunchArgument] = []
    ) {
        self.environmentVariables = environmentVariables
        self.launchArguments = launchArguments
    }

    public init(launchArguments: [LaunchArgument]) {
        environmentVariables = [:]
        self.launchArguments = launchArguments
    }
}
