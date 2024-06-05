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
    /**
     When packages are linked statically, which is the default of Tuist's integration using XcodeProj primitives,
     issues might arise due to missing extensions. This is a [known issue](https://github.com/apple/swift/issues/48561)
     that the SPM circumvents using the `-r` flag with the linker, or the `GENERATE_MASTER_OBJECT_FILE` build setting with the
     packages' targets.

     Opting-into that behaviour can have a negative impact on the final binary size, and therefore we keep it as disable but giving
     developers an option to opt into it easily. When this value is set to true, it applies it to all the packages of the project that are static.
     */
    public var enableMasterObjectFileGenerationInStaticTargets: Bool

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
    ///     - enableMasterObjectFileGenerationInStaticTargets: Sets the `GENERATE_MASTER_OBJECT_FILE` build setting in static
    /// targets.
    public init(
        productTypes: [String: Product] = [:],
        productDestinations: [String: Destinations] = [:],
        baseSettings: Settings = .settings(),
        targetSettings: [String: SettingsDictionary] = [:],
        projectOptions: [String: Project.Options] = [:],
        enableMasterObjectFileGenerationInStaticTargets: Bool = false
    ) {
        self.productTypes = productTypes
        self.productDestinations = productDestinations
        self.baseSettings = baseSettings
        self.targetSettings = targetSettings
        self.projectOptions = projectOptions
        self.enableMasterObjectFileGenerationInStaticTargets = enableMasterObjectFileGenerationInStaticTargets
        dumpIfNeeded(self)
    }
}
