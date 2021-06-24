import Foundation

/// Contains the description of a dependency that can be installed using Swift Package Manager.
public struct SwiftPackageManagerDependencies: Codable, Equatable {
    /// List of packages that will be installed using Swift Package Manager.
    public let packages: [Package]

    /// The `Product` type to be used for SPM targets with `automatic` library type.
    public let automaticProductType: Product

    /// Creates `SwiftPackageManagerDependencies` instance.
    /// - Parameter packages: List of packages that will be installed using Swift Package Manager.
    /// - Parameter productType: The `Product` type to be used for SPM targets with `automatic` library type.
    public init(_ packages: [Package], automaticProductType: Product = .staticLibrary) {
        self.packages = packages
        self.automaticProductType = automaticProductType
    }
}

// MARK: - ExpressibleByArrayLiteral

extension SwiftPackageManagerDependencies: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Package...) {
        packages = elements
        automaticProductType = .staticLibrary
    }
}
