import Foundation

public struct Arguments: Equatable, Codable {
    public let environment: [String: String]
    public let launch: [String: Bool]

    public init(environment: [String: String] = [:],
                launch: [String: Bool] = [:])
    {
        self.environment = environment
        self.launch = launch
    }
}
