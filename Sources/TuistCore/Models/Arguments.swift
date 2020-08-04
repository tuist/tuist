import Foundation

public struct Arguments: Equatable {
    // MARK: - Attributes

    public let environment: [String: String]
    public let launchArguments: [String: Bool]

    // MARK: - Init

    public init(environment: [String: String] = [:],
                launchArguments: [String: Bool] = [:]) {
        self.environment = environment
        self.launchArguments = launchArguments
    }
}
