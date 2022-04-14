import Foundation

/// A collection of Carthage dependencies.
public struct CarthageDependencies: Codable, Equatable {
    /// List of dependencies that will be installed using Carthage.
    public let dependencies: [Dependency]

    /// Creates `CarthageDependencies` instance.
    /// - Parameter dependencies: List of dependencies that can be installed using Carthage.
    public init(_ dependencies: [Dependency]) {
        self.dependencies = dependencies
    }
}

// MARK: - ExpressibleByArrayLiteral

extension CarthageDependencies: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Dependency...) {
        dependencies = elements
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
