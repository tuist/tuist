import Foundation
import TSCBasic
import TuistSupport

// MARK: - Dependencies Graph Error

public enum DependenciesGraphError: FatalError, Equatable {
    /// Thrown when the same dependency is defined more than once.
    case duplicatedDependency(String, [TargetDependency], [TargetDependency])

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
    public let externalDependencies: [String: [TargetDependency]]

    /// Create an instance of `DependenciesGraph` model.
    public init(externalDependencies: [String: [TargetDependency]]) {
        self.externalDependencies = externalDependencies
    }

    /// An empty `DependenciesGraph`.
    public static let none: DependenciesGraph = .init(externalDependencies: [:])
}

extension DependenciesGraph {
    public func merging(with other: Self) throws -> Self {
        let mergedExternalDependencies = try other.externalDependencies.reduce(into: externalDependencies) { result, entry in
            if let alreadyPresent = result[entry.key] {
                throw DependenciesGraphError.duplicatedDependency(entry.key, alreadyPresent, entry.value)
            }

            result[entry.key] = entry.value
        }
        return .init(externalDependencies: mergedExternalDependencies)
    }
}
