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
    case duplicatedDependency(String)

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
        case let .duplicatedDependency(name):
            return "The \(name) dependency is defined more than once across different dependency managers."
        }
    }
}

extension DependenciesGraph {
    public func merging(with other: Self) throws -> Self {
        let mergedThirdPartyDependencies = try thirdPartyDependencies.merging(other.thirdPartyDependencies) { old, _ in
            let name = self.thirdPartyDependencies.first { $0.value == old }!.key
            throw DependenciesGraphError.duplicatedDependency(name)
        }
        return .init(thirdPartyDependencies: mergedThirdPartyDependencies)
    }
}
