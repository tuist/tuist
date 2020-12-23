import Foundation
import TuistSupport

// MARK: - Carthage Dependency

/// CarthageDependency contains the description of a dependency to be fetched with Carthage.
public struct CarthageDependency: Equatable {
    /// Origin of the dependency
    public let origin: Origin

    /// Type of requirement for the given dependency
    public let requirement: Requirement

    /// Set of platforms for  the given dependency
    public let platforms: Set<Platform>

    /// Initializes the carthage dependency with its attributes.
    ///
    /// - Parameters:
    ///   - origin: Origin of the dependency
    ///   - requirement: Type of requirement for the given dependency
    ///   - platforms: Set of platforms for  the given dependency
    public init(
        origin: Origin,
        requirement: Requirement,
        platforms: Set<Platform>
    ) {
        self.origin = origin
        self.requirement = requirement
        self.platforms = platforms
    }

    /// Returns `Cartfile` representation.
    public var cartfileValue: String {
        origin.cartfileValue + " " + requirement.cartfileValue
    }
}

public extension CarthageDependency {
    enum Origin: Equatable {
        case github(path: String)
        case git(path: String)
        case binary(path: String)

        /// Returns `Cartfile` representation.
        public var cartfileValue: String {
            switch self {
            case let .github(path):
                return #"github "\#(path)""#
            case let .git(path):
                return #"git "\#(path)""#
            case let .binary(path):
                return #"binary "\#(path)""#
            }
        }
    }
}

// MARK: - Requirement

public extension CarthageDependency {
    enum Requirement: Equatable {
        case exact(String)
        case upToNext(String)
        case atLeast(String)
        case branch(String)
        case revision(String)

        /// Returns `Cartfile` representation.
        public var cartfileValue: String {
            switch self {
            case let .exact(version):
                return "== \(version)"
            case let .upToNext(version):
                return "~> \(version)"
            case let .atLeast(version):
                return ">= \(version)"
            case let .branch(branch):
                return #""\#(branch)""#
            case let .revision(revision):
                return #""\#(revision)""#
            }
        }
    }
}
