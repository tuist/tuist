import Foundation
import TSCBasic
import TuistSupport

// MARK: - Dependencies Graph Error

public enum DependenciesGraphError: FatalError, Equatable {
    /// Thrown when the same dependency is defined more than once.
    case duplicatedDependency(String, ExternalDependency, ExternalDependency)

    /// Error type.
    public var type: ErrorType {
        switch self {
        case .duplicatedDependency:
            return .abort
        }
    }

    // Error description.
    public var description: String {
        switch self {
        case let .duplicatedDependency(name, first, second):
            return """
            The \(name) dependency is defined twice across different dependency managers:
            First: \(first)
            Second: \(second)
            """
        }
    }
}

// MARK: - Dependencies Graph

/// A directed acyclic graph (DAG) that Tuist uses to represent the dependency tree.
public struct DependenciesGraph: Equatable, Codable {
    /// A dictionary where the keys are the names of dependencies, and the values are the dependencies themselves.
    public let externalDependencies: [String: ExternalDependency]

    /// Create an instance of `DependenciesGraph` model.
    public init(externalDependencies: [String: ExternalDependency]) {
        self.externalDependencies = externalDependencies
    }

    /// An empty `DependenciesGraph`.
    public static let none: DependenciesGraph = .init(externalDependencies: [:])
}

extension DependenciesGraph {
    public func merging(with other: Self) throws -> Self {
        let mergedExternalDependencies = try externalDependencies.merging(other.externalDependencies) { old, new in
            throw DependenciesGraphError.duplicatedDependency(old.name, old, new)
        }
        return .init(externalDependencies: mergedExternalDependencies)
    }
}
