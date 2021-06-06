import Foundation

/// Contains descriptions of dependencies to be fetched with Carthage.
public struct CarthageDependencies: Equatable {
    /// List of depedencies that can be installed using Carthage.
    public let dependencies: [Dependency]

    /// Initializes a new `CarthageDependencies` instance.
    /// - Parameters:
    ///   - dependencies: List of depedencies that can be installed using Carthage.
    public init(
        _ dependencies: [Dependency]
    ) {
        self.dependencies = dependencies
    }

    /// Returns `Cartfile` representation.
    public func cartfileValue() -> String {
        dependencies
            .map(\.cartfileValue)
            .joined(separator: "\n")
    }
}

// MARK: - CarthageDependencies.Dependency

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
}

// MARK: - CarthageDependencies.Requirement

public extension CarthageDependencies {
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
