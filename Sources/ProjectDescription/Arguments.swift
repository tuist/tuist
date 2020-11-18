import Foundation

public struct Arguments: Equatable, Codable {
    public let environment: [String: String]
    public let launchArguments: [LaunchArgument]

    @available(*, deprecated, message: "Use init with `launchArguments: [LaunchArgument]` instead")
    public init(environment: [String: String] = [:],
                launchArguments: [String: Bool]) {
        self.environment = environment
        self.launchArguments = launchArguments.map(LaunchArgument.init)
            .sorted { $0.name < $1.name }
    }

    public init(environment: [String: String] = [:],
                launchArguments: [LaunchArgument] = []) {
        self.environment = environment
        self.launchArguments = launchArguments
    }
}
