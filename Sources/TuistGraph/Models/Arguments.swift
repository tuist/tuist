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

extension Arguments {
    /// Creates a new `Arguments` that merges the contents of the current and given `Arguments`.
    ///
    /// If there are duplicate keys, the value of the current one will be preserved.
    ///
    /// - Parameter arguments: The `Arguments` to merge.
    /// - Returns: A new `Arguments` with the merged contents.
    public func merging(with arguments: Arguments) -> Arguments {
        Arguments(
            environment: environment.merging(
                arguments.environment,
                uniquingKeysWith: { a, _ in a }
            ),
            launchArguments: launchArguments + arguments.launchArguments.filter { argument in
                !self.launchArguments.contains(where: { argument.name == $0.name })
            }
        )
    }
}
