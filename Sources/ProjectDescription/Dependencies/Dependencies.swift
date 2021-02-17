import Foundation

/// A `Dependencies` manifest allows for defining external dependencies for Tuist.
public struct Dependencies: Codable, Equatable {
    /// The description of dependency that can by installed using Carthage.
    public let carthageDependencies: CarthageDependencies?

    /// Initializes a new `Dependencies` manifest instance.
    /// - Parameter carthageDependencies: The description of dependency that can by installed using Carthage. Pass `nil` value if you don't have dependencies from Carthage.
    public init(carthageDependencies: CarthageDependencies? = nil) {
        self.carthageDependencies = carthageDependencies
        dumpIfNeeded(self)
    }
}
