import Foundation

/// A collection of external dependencies.
///
/// Learn how to get started with `Dependencies.swift` manifest [here](https://docs.tuist.io/guides/dependencies).
///
/// ```swift
/// import ProjectDescription
///
/// let dependencies = Dependencies(
///     carthage: [
///         .github(path: "Alamofire/Alamofire", requirement: .exact("5.0.4")),
///     ],
///     swiftPackageManager: [
///         .remote(url: "https://github.com/Alamofire/Alamofire", requirement: / .upToNextMajor(from: "5.0.0")),
///     ],
///     platforms: [.iOS]
/// )
/// ```
public struct Dependencies: Codable, Equatable {
    /// The description of dependencies that can be installed using Carthage.
    public let carthage: CarthageDependencies?

    /// The description of dependencies that can be installed using Swift Package Manager.
    public let swiftPackageManager: SwiftPackageManagerDependencies?

    /// List of platforms for which you want to install dependencies.
    public let platforms: Set<Platform>

    /// Creates a new `Dependencies` manifest instance.
    /// - Parameters:
    ///   - carthage: The description of dependencies that can be installed using Carthage. Pass `nil` if you don't have dependencies from Carthage.
    ///   - swiftPackageManager: The description of dependencies that can be installed using SPM. Pass `nil` if you don't have dependencies from SPM.
    ///   - platforms: Set of platforms for which you want to install dependencies.
    public init(
        carthage: CarthageDependencies? = nil,
        swiftPackageManager: SwiftPackageManagerDependencies? = nil,
        platforms: Set<Platform> = Set(Platform.allCases)
    ) {
        self.carthage = carthage
        self.swiftPackageManager = swiftPackageManager
        self.platforms = platforms
        dumpIfNeeded(self)
    }
}
