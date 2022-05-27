import Foundation

/// A collection of Swift Package Manager dependencies.
///
/// Example:
///
/// ```swift
/// let packageManager = SwiftPackageManagerDependencies(
///     packages: [
///         .package(url: "https://github.com/Alamofire/Alamofire", .upToNextMajor(from: "5.6.0")),
///         .local(path: "MySwiftPackage")
///     ],
///     baseSettings: .settings(configurations: [.debug(name: .debug), .release(name: .release)]),
///     targetSettings: ["MySwiftPackageTarget": ["IPHONEOS_DEPLOYMENT_TARGET": SettingValue.string("13.0")]],
///     generationOptions: ["MySwiftPackage":  .options(.disableSynthesizedResourceAccessors: false)]
/// )
/// ```

public struct SwiftPackageManagerDependencies: Codable, Equatable {
    /// List of packages that will be installed using Swift Package Manager.
    public let packages: [Package]

    /// The custom `Product` type to be used for SPM targets.
    public let productTypes: [String: Product]

    // The base settings to be used for targets generated from SwiftPackageManager
    public let baseSettings: Settings

    // Additional settings to be added to targets generated from SwiftPackageManager.
    public let targetSettings: [String: SettingsDictionary]

    /// Custom project configurations to be used for projects generated from SwiftPackageManager.
    public let generationOptions: [String: ProjectDescription.Project.Options]

    /// Creates `SwiftPackageManagerDependencies` instance.
    /// - Parameter packages: List of packages that will be installed using Swift Package Manager.
    /// - Parameter productTypes: The custom `Product` types to be used for SPM targets.
    /// - Parameter baseSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    /// - Parameter targetSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    /// - Parameter generationOptions: Custom project configurations to be used for projects generated from SwiftPackageManager.

    public init(
        _ packages: [Package],
        productTypes: [String: Product] = [:],
        baseSettings: Settings = .settings(),
        targetSettings: [String: SettingsDictionary] = [:],
        generationOptions: [String: ProjectDescription.Project.Options] = [:]
    ) {
        self.packages = packages
        self.productTypes = productTypes
        self.baseSettings = baseSettings
        self.targetSettings = targetSettings
        self.generationOptions = generationOptions
    }
}

// MARK: - ExpressibleByArrayLiteral

extension SwiftPackageManagerDependencies: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Package...) {
        self.init(elements)
    }
}
