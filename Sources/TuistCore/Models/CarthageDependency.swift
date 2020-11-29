import Foundation
import TuistSupport

// MARK: - Carthage Dependency Error

enum CarthageDependencyError: FatalError, Equatable {
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
        case let .rangeRequirementNotSupported(dependencyName, fromVersion, toVersion):
            return "\(dependencyName) in version between \(fromVersion) and \(toVersion) can not be installed. Carthage do not support versions range requirement in Cartfile."
        }
    }
}

// MARK: - Carthage Dependency

/// CarthageDependency contains the description of a dependency to be fetched with Carthage.
public struct CarthageDependency: Equatable {
    /// Name of the dependency
    public let name: String

    /// Type of requirement for the given dependency
    public let requirement: Requirement

    /// Set of platforms for  the given dependency
    public let platforms: Set<Platform>

    /// Initializes the carthage dependency with its attributes.
    ///
    /// - Parameters:
    ///   - name: Name of the dependency
    ///   - requirement: Type of requirement for the given dependency
    ///   - platforms: Set of platforms for  the given dependency
    public init(
        name: String,
        requirement: Requirement,
        platforms: Set<Platform>
    ) {
        self.name = name
        self.requirement = requirement
        self.platforms = platforms
    }

    /// Returns `Cartfile` representation.
    public func cartfileValue() throws -> String {
        switch requirement {
        case let .exact(version):
            return #"github "\#(name)" == \#(version)"#
        case let .upToNextMajor(version):
            return #"github "\#(name)" ~> \#(version)"#
        case let .upToNextMinor(version):
            return #"github "\#(name)" ~> \#(version)"#
        case let .range(fromVersion, toVersion):
            throw CarthageDependencyError.rangeRequirementNotSupported(dependencyName: name, fromVersion: fromVersion, toVersion: toVersion)
        case let .branch(branch):
            return #"github "\#(name)" "\#(branch)""#
        case let .revision(revision):
            return #"github "\#(name)" "\#(revision)""#
        }
    }
}
