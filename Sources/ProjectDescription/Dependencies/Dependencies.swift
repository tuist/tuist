import Foundation

/// A `Dependencies` manifest allows for defining external dependencies for Tuist.
public struct Dependencies: Codable, Equatable {
    /// The description of dependency that can be installed using Carthage.
    public let carthage: CarthageDependencies?
    /// The description of dependency that can be installed using Swift Package Manager.
    public let swiftPackageManager: SwiftPackageManagerDependencies?

    /// Initializes a new `Dependencies` manifest instance.
    /// - Parameter carthage: The description of dependencies that can be installed using Carthage. Pass `nil` if you don't have dependencies from Carthage.
    /// - Parameter swiftPackageManager: The description of dependency that can be installed using Swift Package Manager. Pass `nil` if you don't have dependencies from SPM.
    public init(
        carthage: CarthageDependencies? = nil,
        swiftPackageManager: SwiftPackageManagerDependencies? = nil
    ) {
        self.carthage = carthage
        self.swiftPackageManager = swiftPackageManager
        dumpIfNeeded(self)
    }
}
