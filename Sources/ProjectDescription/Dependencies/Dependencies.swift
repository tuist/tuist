import Foundation

/// A `Dependencies` manifest allows for defining external dependencies for Tuist.
public struct Dependencies: Codable, Equatable {
    /// The description of dependency that can be installed using Carthage.
    public let carthage: CarthageDependencies?

    /// Initializes a new `Dependencies` manifest instance.
    /// - Parameter carthage: The description of dependencies that can be installed using Carthage. Pass `nil` if you don't have dependencies from Carthage.
    public init(carthage: CarthageDependencies? = nil) {
        self.carthage = carthage
        dumpIfNeeded(self)
    }
}
