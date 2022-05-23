import Foundation

/// A collection of Swift Package Manager dependencies.
public struct SwiftPackageManagerDependencies: Codable, Equatable {
    /// List of packages that will be installed using Swift Package Manager.
    public let packages: [Package]

    /// The custom `Product` type to be used for SPM targets.
    public let productTypes: [String: Product]

    // The base settings to be used for targets generated from SwiftPackageManager
    public let baseSettings: Settings

    // Additional settings to be added to targets generated from SwiftPackageManager.
    public let targetSettings: [String: SettingsDictionary]

    /// The project options.
    public let options: Project.Options

    /// The resource synthesizers for the project to generate accessors for resources.
    public let resourceSynthesizers: [ResourceSynthesizer]

    /// Creates `SwiftPackageManagerDependencies` instance.
    /// - Parameter packages: List of packages that will be installed using Swift Package Manager.
    /// - Parameter productTypes: The custom `Product` types to be used for SPM targets.
    /// - Parameter baseSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    /// - Parameter targetSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    /// - Parameter options: Options to control automatic resource accessors generation for Swift Packages.
    /// - Parameter resourceSynthesizers: The resource synthesizers for the project to generate accessors for resources.
    public init(
        _ packages: [Package],
        productTypes: [String: Product] = [:],
        baseSettings: Settings = .settings(),
        targetSettings: [String: SettingsDictionary] = [:],
        options: Project.Options = .defaultSwiftPackageOptions(),
        resourceSynthesizers: [ResourceSynthesizer] = .default
    ) {
        self.packages = packages
        self.productTypes = productTypes
        self.baseSettings = baseSettings
        self.targetSettings = targetSettings
        self.options = options
        self.resourceSynthesizers = resourceSynthesizers
    }
}

// MARK: - ExpressibleByArrayLiteral

extension SwiftPackageManagerDependencies: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Package...) {
        self.init(elements)
    }
}
