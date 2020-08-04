import Foundation

public struct Arguments: Equatable, Codable {
    public let environment: [String: String]
    public let launchArguments: [String: Bool]

    public init(environment: [String: String] = [:],
                launchArguments: [String: Bool] = [:])
    {
        self.environment = environment
        self.launchArguments = launchArguments
    }
}
