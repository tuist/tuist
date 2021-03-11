import Foundation

/// Contains the description of a dependency that can be installed using Swift Package Manager.
public struct SwiftPackageManagerDependencies: Equatable {
    /// List of packages that will be installed using Swift Package Manager.
    public let packages: [Package]

    /// Initializes a new `SwiftPackageManagerDependencies` instance.
    /// - Parameter packages: List of packages that will be installed using Swift Package Manager.
    public init(_ packages: [Package]) {
        self.packages = packages
    }
}
