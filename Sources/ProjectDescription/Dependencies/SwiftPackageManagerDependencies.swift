import Foundation

/// Contains the description of a dependency that can be installed using Swift Package Manager.
public struct SwiftPackageManagerDependencies: Codable, Equatable {
    /// List of packages that will be installed using Swift Package Manager.
    public let packages: [Package]

    /// The custom `Product` type to be used for SPM targets.
    public let productTypes: [String: Product]

    // Additional settings to be added to targets generated from SwiftPackageManager.
    public let targetSettings: [String: SettingsDictionary]

    /// Creates `SwiftPackageManagerDependencies` instance.
    /// - Parameter packages: List of packages that will be installed using Swift Package Manager.
    /// - Parameter productTypes: The custom `Product` types to be used for SPM targets.
    /// - Parameter targetSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    public init(
      _ packages: [Package],
      productTypes: [String: Product] = [:],
      targetSettings: [String: SettingsDictionary] = [:]
    ) {
        self.packages = packages
        self.productTypes = productTypes
        self.targetSettings = targetSettings
    }
}

// MARK: - ExpressibleByArrayLiteral

extension SwiftPackageManagerDependencies: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Package...) {
        packages = elements
        productTypes = [:]
        targetSettings = [:]
    }
}
