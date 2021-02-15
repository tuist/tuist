import Foundation

/// A `Dependencies` manifest allows for defining external dependencies for Tuist.
public struct Dependencies: Codable, Equatable {
    public let carthageDependencies: CarthageDependencies?

    /// Initializes a new `Dependencies` manifest instance.
    public init(carthageDependencies: CarthageDependencies? = nil) {
        self.carthageDependencies = carthageDependencies
        dumpIfNeeded(self)
    }
}
