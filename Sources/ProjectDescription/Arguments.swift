import Foundation

/// A collection of arguments and environment variables.
public struct Arguments: Equatable, Codable {
    public let environment: [String: String]
    public let launchArguments: [LaunchArgument]

    public init(
        environment: [String: String] = [:],
        launchArguments: [LaunchArgument] = []
    ) {
        self.environment = environment
        self.launchArguments = launchArguments
    }
}
