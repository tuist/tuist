import Foundation

/// Arguments contain commandline arguments passed on launch and Environment variables.
public struct Arguments: Codable {
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

extension Arguments: Equatable {
    /// Implement `Equatable` manually so order of arguments doesn't matter.
    public static func == (lhs: Arguments, rhs: Arguments) -> Bool {
        lhs.environment == rhs.environment
            && lhs.launchArguments.sorted { $0.name < $1.name }
            == rhs.launchArguments.sorted { $0.name == $1.name }
    }
}
