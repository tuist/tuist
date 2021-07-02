import Foundation

/// A `Dependencies` manifest allows for defining external dependencies for Tuist.
public struct Dependencies: Codable, Equatable {
    /// The description of dependencies that can be installed using Carthage.
    public let carthage: CarthageDependencies?

    /// The description of dependencies that can be installed using Swift Package Manager.
    public let swiftPackageManager: SwiftPackageManagerDependencies?

    /// Set of platforms for which you want to install dependencies.
    public let platforms: Set<Platform>

    /// Set of deployment targets you want to set for dependencies not defining a deployment target.
    public let deploymentTargets: Set<DeploymentTarget>

    /// Initializes a new `Dependencies` manifest instance.
    /// - Parameters:
    ///   - carthage: The description of dependencies that can be installed using Carthage. Pass `nil` if you don't have dependencies from Carthage.
    ///   - swiftPackageManager: The description of dependencies that can be installed using SPM. Pass `nil` if you don't have dependencies from SPM.
    ///   - platforms: List of platforms for which you want to install dependencies.
    public init(
        carthage: CarthageDependencies? = nil,
        swiftPackageManager: SwiftPackageManagerDependencies? = nil,
        platforms: Set<Platform> = Set(Platform.allCases),
        deploymentTargets: Set<DeploymentTarget> = []
    ) {
        self.carthage = carthage
        self.swiftPackageManager = swiftPackageManager
        self.platforms = platforms
        self.deploymentTargets = deploymentTargets
        dumpIfNeeded(self)
    }
}
