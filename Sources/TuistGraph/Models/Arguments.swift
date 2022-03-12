import Foundation

/// Arguments contain commandline arguments passed on launch and Environment variables.
public struct Arguments: Equatable, Codable {
    // MARK: - Attributes

    /// The environment variables that are passed by the scheme when running a scheme action.
    public let environment: [String: String]
    /// Launch arguments that are passed by the scheme when running a scheme action.
    public let launchArguments: [LaunchArgument]

    // MARK: - Init

    public init(
        environment: [String: String] = [:],
        launchArguments: [LaunchArgument] = []
    ) {
        self.environment = environment
        self.launchArguments = launchArguments
    }
}
