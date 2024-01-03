import Foundation

/// A collection of arguments and environment variables.
public struct Arguments: Equatable, Codable {
    public var environmentVariables: [String: EnvironmentVariable]
    public var launchArguments: [LaunchArgument]

    @available(*, deprecated, message: "please use environmentVariables instead")
    public init(
        environment: [String: String] = [:],
        launchArguments: [LaunchArgument] = []
    ) {
        environmentVariables = environment.mapValues { value in
            EnvironmentVariable(value: value, isEnabled: true)
        }
        self.launchArguments = launchArguments
    }

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
