import Foundation

/// Arguments contain commandline arguments passed on launch and Environment variables.
public struct Arguments: Codable {
    // MARK: - Attributes

    /// Launch arguments that are passed by the scheme when running a scheme action.
    public let launchArguments: [LaunchArgument]
    /// The environment variables that are passed by the scheme when running a scheme action.
    public let environmentVariables: [String: EnvironmentVariable]

    // MARK: - Init

    public init(
        environmentVariables: [String: EnvironmentVariable] = [:],
        launchArguments: [LaunchArgument] = []
    ) {
        self.environmentVariables = environmentVariables
        self.launchArguments = launchArguments
    }
}

extension Arguments: Equatable {
    /// Implement `Equatable` manually so order of arguments doesn't matter.
    public static func == (lhs: Arguments, rhs: Arguments) -> Bool {
        lhs.environmentVariables == rhs.environmentVariables
            && lhs.launchArguments.sorted { $0.name < $1.name }
            == rhs.launchArguments.sorted { $0.name == $1.name }
    }
}
