import Foundation

/// Contains the description of a dependency that can be fetched with Swift Package Manager.
public struct SwiftPackageManagerDependency: Equatable {
    /// Type of package.
    public let package: Package
    
    /// Initializes the Swift Package Manager dependency with its attributes.
    ///
    /// - Parameter package: Type of package.
    public init(package: Package) {
        self.package = package
    }
}
