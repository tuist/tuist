import Foundation

/// A custom Swift Package Manager configuration
///
///
/// ```swift
/// // swift-tools-version: 5.9
/// import PackageDescription
///
/// #if TUIST
///     import ProjectDescription
///     import ProjectDescriptionHelpers
///
///     let packageSettings = PackageSettings(
///         productTypes: [
///             "Alamofire": .framework, // default is .staticFramework
///         ]
///     )
/// #endif
///
/// let package = Package(
///     name: "PackageName",
///     dependencies: [
///         .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
///     ]
/// )
/// ```
public struct PackageSettings: Codable, Equatable {
    /// The custom `Product` type to be used for SPM targets.
    public var productTypes: [String: Product]

    /// Custom product destinations where key of the dictionary is the name of the SPM product and the value contains the
    /// supported destinations.
    /// **Note**: This setting should only be used when using Tuist for SPM package projects, _not_ for your external
    /// dependencies.
    /// SPM implicitly always supports all platforms, but some commands like `tuist cache` depend on destinations being explicit.
    /// If a product does not support all destinations, you can use `productDestinations` to make the supported destinations
    /// explicit.
    public var productDestinations: [String: Destinations]

    // The base settings to be used for targets generated from SwiftPackageManager
    public var baseSettings: Settings

    // Additional settings to be added to targets generated from SwiftPackageManager.
    public var targetSettings: [String: SettingsDictionary]

    /// Custom project configurations to be used for projects generated from SwiftPackageManager.
    public var projectOptions: [String: Project.Options]

    /// Creates `PackageSettings` instance for custom Swift Package Manager configuration.
    /// - Parameters:
    ///     - productTypes: The custom `Product` types to be used for SPM targets.
    ///     - productDestinations: Custom destinations to be used for SPM products.
    ///     - baseSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    ///     - targetSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    ///     - projectOptions: Custom project configurations to be used for projects generated from SwiftPackageManager.
    public init(
        productTypes: [String: Product] = [:],
        productDestinations: [String: Destinations] = [:],
        baseSettings: Settings = .settings(),
        targetSettings: [String: SettingsDictionary] = [:],
        projectOptions: [String: Project.Options] = [:]
    ) {
        self.productTypes = productTypes
        self.productDestinations = productDestinations
        self.baseSettings = baseSettings
        self.targetSettings = targetSettings
        self.projectOptions = projectOptions
        dumpIfNeeded(self)
    }
}
