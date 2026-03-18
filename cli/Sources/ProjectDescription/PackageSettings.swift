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
public struct PackageSettings: Codable, Equatable, Sendable {
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

    /// The base settings to be used for targets generated from SwiftPackageManager
    public var baseSettings: Settings

    /// Expected signatures for Swift Package Manager binary targets.
    /// The first-level key is the package name and the second-level key is the binary target name.
    public var binaryTargetSignatures: [String: [String: XCFrameworkSignature]]

    /// Additional settings to be added to targets generated from SwiftPackageManager.
    public var targetSettings: [String: Settings]

    /// Custom project configurations to be used for projects generated from SwiftPackageManager.
    public var projectOptions: [String: Project.Options]

    /// Creates `PackageSettings` instance for custom Swift Package Manager configuration.
    /// - Parameters:
    ///     - productTypes: The custom `Product` types to be used for SPM targets.
    ///     - productDestinations: Custom destinations to be used for SPM products.
    ///     - baseSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    ///     - binaryTargetSignatures: Expected signatures keyed by package name and binary target name.
    ///     - targetSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    ///     - projectOptions: Custom project configurations to be used for projects generated from SwiftPackageManager.
    public init(
        productTypes: [String: Product] = [:],
        productDestinations: [String: Destinations] = [:],
        baseSettings: Settings = .settings(),
        binaryTargetSignatures: [String: [String: XCFrameworkSignature]] = [:],
        targetSettings: [String: Settings] = [:],
        projectOptions: [String: Project.Options] = [:]
    ) {
        self.productTypes = productTypes
        self.productDestinations = productDestinations
        self.baseSettings = baseSettings
        self.binaryTargetSignatures = binaryTargetSignatures
        self.targetSettings = targetSettings
        self.projectOptions = projectOptions
        dumpIfNeeded(self)
    }

    /// Creates `PackageSettings` instance for custom Swift Package Manager configuration.
    /// - Parameters:
    ///     - productTypes: The custom `Product` types to be used for SPM targets.
    ///     - productDestinations: Custom destinations to be used for SPM products.
    ///     - baseSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    ///     - binaryTargetSignatures: Expected signatures keyed by package name and binary target name.
    ///     - targetSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    ///     - projectOptions: Custom project configurations to be used for projects generated from SwiftPackageManager.
    @available(
        *,
        deprecated,
        renamed: "init(productTypes:productDestinations:baseSettings:targetSettings:projectOptions:)",
        message: """
        Consider using the 'Settings' type for parameter 'targetSettings' instead of 'SettingsDictionary'.
        """
    )
    public init(
        productTypes: [String: Product] = [:],
        productDestinations: [String: Destinations] = [:],
        baseSettings: Settings = .settings(),
        binaryTargetSignatures: [String: [String: XCFrameworkSignature]] = [:],
        targetSettings: [String: SettingsDictionary],
        projectOptions: [String: Project.Options] = [:]
    ) {
        self.productTypes = productTypes
        self.productDestinations = productDestinations
        self.baseSettings = baseSettings
        self.binaryTargetSignatures = binaryTargetSignatures
        self.targetSettings = targetSettings.mapValues { .settings(base: $0) }
        self.projectOptions = projectOptions
        dumpIfNeeded(self)
    }
}
