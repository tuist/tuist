import Foundation

/// A `Dependencies` manifest allows for defining external dependencies for Tuist.
public struct Dependencies: Codable, Equatable {
    /// The description of dependency that can be installed using Carthage.
    public let carthage: CarthageDependencies?
    /// The description of dependency that can be installed using Swift Package Manager.
    public let swiftPackageManager: SwiftPackageManagerDependencies?
    /// List of platforms for which you want to install depedencies.
    public let platforms: Set<Platform>

    /// Initializes a new `Dependencies` manifest instance.
    /// - Parameters:
    ///   - carthage: The description of dependencies that can be installed using Carthage. Pass `nil` if you don't have dependencies from Carthage.
    ///   - swiftPackageManager: WIP - it doesnt ready for use, pass `nil`.
    ///   - platforms: List of platforms for which you want to install depedencies.
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
