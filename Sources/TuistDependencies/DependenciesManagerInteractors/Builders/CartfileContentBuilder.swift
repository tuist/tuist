import TSCBasic
import TuistCore
import TuistSupport

// MARK: - Cartfile Content Builder Error

enum CartfileContentBuilderError: FatalError, Equatable {
    /// Thrown when `Requirement.range` has been used for `carthage`'s dependency.
    case rangeRequirementNotSupported(dependencyName: String, fromVersion: String, toVersion: String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .rangeRequirementNotSupported:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .rangeRequirementNotSupported(dependencyName, _, _):
            return "\(dependencyName) can not be installed. Carthage do not support versions range requirement in Cartfile."
        }
    }
}

// MARK: - Cartfile Content Builder

final class CartfileContentBuilder {
    // MARK: - State

    private let dependencies: [CarthageDependency]

    // MARK: - Init

    init(dependencies: [CarthageDependency]) {
        self.dependencies = dependencies
    }

    // MARK: - Build

    func build() throws -> String {
        try dependencies
            .map { try $0.toString() }
            .joined(separator: "\n")
    }
}

private extension CarthageDependency {
    func toString() throws -> String {
        switch requirement {
        case let .exact(version):
            return #"github "\#(name)" == \#(version)"#
        case let .upToNextMajor(version):
            return #"github "\#(name)" ~> \#(version)"#
        case let .upToNextMinor(version):
            return #"github "\#(name)" ~> \#(version)"#
        case let .range(fromVersion, toVersion):
            throw CartfileContentBuilderError.rangeRequirementNotSupported(dependencyName: name, fromVersion: fromVersion, toVersion: toVersion)
        case let .branch(branch):
            return #"github "\#(name)" "\#(branch)""#
        case let .revision(revision):
            return #"github "\#(name)" "\#(revision)""#
        }
    }
}
