import Foundation

/// The structure defining the output schema of an Xcode scheme.
public struct Scheme: Codable, Equatable {
    /// The name of the scheme.
    public let name: String

    /// The targets that can be tested via this scheme.
    public let testActionTargets: [String]?

    public init(name: String, testActionTargets: [String]? = nil) {
        self.name = name
        self.testActionTargets = testActionTargets
    }
}
