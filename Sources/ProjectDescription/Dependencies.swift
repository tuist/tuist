import Foundation

/// A `Dependencies` manifest allows for defining external dependencies for Tuist.
public struct Dependencies: Codable, Equatable {
    /// List of dependencies.
    public let dependencies: [Dependency]
    
    /// Initializes a new `Dependencies` manifest instance.
    /// - Parameter dependencies: List of dependencies.
    public init(_ dependencies: [Dependency] = []) {
        self.dependencies = dependencies
        dumpIfNeeded(self)
    }
}
