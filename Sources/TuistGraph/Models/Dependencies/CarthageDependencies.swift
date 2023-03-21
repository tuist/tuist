import Foundation

/// Contains descriptions of dependencies to be fetched with Carthage.
public struct CarthageDependencies: Equatable {
    /// List of dependencies that can be installed using Carthage.
    public let dependencies: [Dependency]

    /// List of options that can be used on Carthage command.
    public let options: Options

    /// Initializes a new `CarthageDependencies` instance.
    /// - Parameters:
    ///   - dependencies: List of dependencies that can be installed using Carthage.
    ///   - options: Set up Carthage's options.
    public init(
        _ dependencies: [Dependency],
        _ options: Options = .init()
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
    /// A set of available options when running Carthage on Tuist.
    public struct Options: Equatable {
        /// Don't use downloaded binaries when possible
        public let noUseBinaries: Bool

        /// Use authentication credentials from `~/.netrc` file when downloading binary only frameworks.
        public let useNetRC: Bool

        /// Use cached builds when possible
        public let cacheBuilds: Bool

        /// Use the new resolver codeline when calculating dependencies.
        public let newResolver: Bool

        public init(noUseBinaries: Bool = true, useNetRC: Bool = true, cacheBuilds: Bool = true, newResolver: Bool = true) {
            self.noUseBinaries = noUseBinaries
            self.useNetRC = useNetRC
            self.cacheBuilds = cacheBuilds
            self.newResolver = newResolver
        }
    }
}
