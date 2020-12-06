import Foundation
import TuistSupport

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
    public func cartfileValue() -> String {
        switch requirement {
        case let .exact(version):
            return #"github "\#(name)" == \#(version)"#
        case let .upToNextMajor(version):
            return #"github "\#(name)" ~> \#(version)"#
        case let .upToNextMinor(version):
            return #"github "\#(name)" ~> \#(version)"#
        case let .branch(branch):
            return #"github "\#(name)" "\#(branch)""#
        case let .revision(revision):
            return #"github "\#(name)" "\#(revision)""#
        }
    }
}

// MARK: - Requirement

public extension CarthageDependency {
    enum Requirement: Equatable {
        case exact(String)
        case upToNextMajor(String)
        case upToNextMinor(String)
        case branch(String)
        case revision(String)
    }
}
