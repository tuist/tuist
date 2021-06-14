import Foundation
import TSCBasic
import TuistSupport

/// A directed acyclic graph (DAG) that Tuist uses to represent the third party dependency tree.
public struct DependenciesGraph: Equatable, Codable {
    /// A dictionary where the keys are the names of dependencies, and the values are the dependencies themselves.
    public let thirdPartyDependencies: [String: ThirdPartyDependency]

    /// Create an instance of `DependenciesGraph` model.
    public init(
        thirdPartyDependencies: [String: ThirdPartyDependency]
    ) {
        self.thirdPartyDependencies = thirdPartyDependencies
    }
}

public enum DependenciesGraphError: FatalError, Equatable {
    /// Thrown when the same dependency is defined more than once.
    case duplicatedDependency(String, ThirdPartyDependency, ThirdPartyDependency)

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

extension DependenciesGraph {
    public func merging(with other: Self) throws -> Self {
        let mergedThirdPartyDependencies = try thirdPartyDependencies.merging(other.thirdPartyDependencies) { old, new in
            throw DependenciesGraphError.duplicatedDependency(old.name, old, new)
        }
        return .init(thirdPartyDependencies: mergedThirdPartyDependencies)
    }
}
