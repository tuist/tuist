import Foundation

/// Contains descriptions of dependencies to be fetched with Carthage.
public struct CarthageDependencies: Equatable {
    /// List of dependencies that can be installed using Carthage.
    public let dependencies: [Dependency]

    /// List of options that can be used on Carthage command.
    public let options: Set<Options>

    /// Initializes a new `CarthageDependencies` instance.
    /// - Parameters:
    ///   - dependencies: List of dependencies that can be installed using Carthage.
    ///   - options: Set of options that can be used on Carthage.
    public init(
        _ dependencies: [Dependency],
        _ options: Set<Options> = [.noUseBinaries, .useNetRC, .cacheBuilds, .newResolver]
    ) {
        self.dependencies = dependencies
        self.options = options
    }

    /// Returns `Cartfile` representation.
    public func cartfileValue() -> String {
        dependencies
            .map(\.cartfileValue)
            .joined(separator: "\n")
    }
}

// MARK: - CarthageDependencies.Dependency

extension CarthageDependencies {
    public enum Dependency: Equatable {
        /// GitHub repositories (both GitHub.com and GitHub Enterprise).
        case github(path: String, requirement: Requirement)
        /// Other Git repositories.
        case git(path: String, requirement: Requirement)
        /// Dependencies that are only available as compiled binary `.framework`s.
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

extension CarthageDependencies {
    public enum Requirement: Equatable {
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

// MARK: - CarthageDependencies.Options

extension CarthageDependencies {
    public enum Options: String {
        /// Don't use downloaded binaries when possible
        case noUseBinaries = "--no-use-binaries"

        /// Use authentication credentials from ~/.netrc file when downloading binary only frameworks.
        case useNetRC = "--use-netrc"

        /// Use cached builds when possible
        case cacheBuilds = "--cache-builds"

        /// Use the new resolver codeline when calculating dependencies.
        case newResolver = "--new-resolver"
    }
}
