import Foundation

public struct Arguments: Equatable {
    // MARK: - Attributes

    public let environment: [String: String]
    public let launchArguments: [LaunchArgument]

    // MARK: - Init

    public init(environment: [String: String] = [:],
                launchArguments: [LaunchArgument] = [])
    {
        self.environment = environment
        self.launchArguments = launchArguments
    }
}
