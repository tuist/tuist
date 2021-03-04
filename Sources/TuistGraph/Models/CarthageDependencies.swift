import Foundation

/// Contains descriptions of dependencies to be fetched with Carthage.
public struct CarthageDependencies: Equatable {
    /// List of depedencies that can be installed using Carthage.
    public let dependencies: [Dependency]
    /// List of platforms for which you want to install depedencies.
    public let platforms: Set<Platform>
    /// Indicates whether Carthage produces XCFrameworks or regular frameworks.
    public let useXCFrameworks: Bool
    /// Indicates whether Carthage rebuilds the dependency from source instead of using downloaded binaries when possible.
    public let noUseBinaries: Bool

    /// Initializes the carthage dependency with its attributes.
    public init(
        _ dependencies: [Dependency],
        platforms: Set<Platform>,
        useXCFrameworks: Bool,
        noUseBinaries: Bool
    ) {
        self.dependencies = dependencies
        self.platforms = platforms
        self.useXCFrameworks = useXCFrameworks
        self.noUseBinaries = noUseBinaries
    }

    /// Returns `Cartfile` representation.
    public func cartfileValue() -> String {
        dependencies
            .map(\.cartfileValue)
            .joined(separator: "\n")
    }
}

public extension CarthageDependencies {
    enum Dependency: Equatable {
        case github(path: String, requirement: Requirement)
        case git(path: String, requirement: Requirement)
        case binary(path: String, requirement: Requirement)

        /// Returns `Cartfile` representation.
        public var cartfileValue: String {
            switch self {
            case let .github(path, requirement):
                return #"github "\#(path)" \#(requirement.cartfileValue)"#
            case let .git(path, requirement):
                return #"git "\#(path)" \#(requirement.cartfileValue)"#
            case let .binary(path, requirement):
                return #"binary "\#(path)" \#(requirement.cartfileValue)"#
            }
        }
    }

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
