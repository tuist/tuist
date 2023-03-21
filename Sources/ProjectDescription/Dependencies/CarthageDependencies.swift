import Foundation

/// A collection of Carthage dependencies.
public struct CarthageDependencies: Codable, Equatable {
    /// List of dependencies that will be installed using Carthage.
    public let dependencies: [Dependency]
    /// Set up Carthage's options.
    public let options: Options

    /// Creates `CarthageDependencies` instance.
    /// - Parameter dependencies: List of dependencies that can be installed using Carthage.
    /// - Parameter options: Set up Carthage's options.
    public init(_ dependencies: [Dependency], _ options: Options = .init()) {
        self.dependencies = dependencies
        self.options = options
    }
}

// MARK: - ExpressibleByArrayLiteral

extension CarthageDependencies: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Dependency...) {
        dependencies = elements
        options = .init()
    }
}

// MARK: - CarthageDependencies.Dependency & CarthageDependencies.Requirement & CarthageDependencies.Options

extension CarthageDependencies {
    /// Specifies origin of Carthage dependency.
    public enum Dependency: Codable, Equatable {
        /// GitHub repositories (both GitHub.com and GitHub Enterprise).
        case github(path: String, requirement: Requirement)
        /// Other Git repositories.
        case git(path: String, requirement: Requirement)
        /// Dependencies that are only available as compiled binary `.framework`s.
        case binary(path: String, requirement: Requirement)
    }

    /// Specifies version requirement for Carthage dependency.
    public enum Requirement: Codable, Equatable {
        case exact(Version)
        case upToNext(Version)
        case atLeast(Version)
        case branch(String)
        case revision(String)
    }
}

// MARK: - CarthageDependencies.Options

extension CarthageDependencies {
    /// A set of available options when running Carthage on Tuist.
    public struct Options: Codable, Equatable {
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
