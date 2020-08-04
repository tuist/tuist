import Foundation

public struct Arguments: Equatable {
    // MARK: - Attributes

    public let environment: [String: String]
    public let launch: [String: Bool]

    // MARK: - Init

    public init(environment: [String: String] = [:],
                launch: [String: Bool] = [:])
    {
        self.environment = environment
        self.launch = launch
    }
}
