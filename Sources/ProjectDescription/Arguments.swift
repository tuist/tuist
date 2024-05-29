import Foundation

/// A collection of arguments and environment variables.
public struct Arguments: Equatable, Codable, Sendable {
    public var environmentVariables: [String: EnvironmentVariable]
    public var launchArguments: [LaunchArgument]

    public static func arguments(
        environmentVariables: [String: EnvironmentVariable] = [:],
        launchArguments: [LaunchArgument] = []
    ) -> Self {
        self.init(environmentVariables: environmentVariables, launchArguments: launchArguments)
    }
}
