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

    /// The default product type (usually static framework)
    public var baseProductType: Product

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

    /// Expected signatures for Swift Package Manager binary targets keyed by binary target name.
    public var expectedSignatures: [String: XCFrameworkSignature]

    /// Additional settings to be added to targets generated from SwiftPackageManager.
    public var targetSettings: [String: Settings]

    /// Custom project configurations to be used for projects generated from SwiftPackageManager.
    public var projectOptions: [String: Project.Options]

    /// Targets that should use buildable folders instead of explicit file references.
    /// When a target name is included in this set, its source files will be added as a
    /// synchronized folder reference (buildable folder) instead of individual file references.
    /// This eliminates the need to regenerate the project when files are added or removed.
    /// **Note**: Requires Xcode 16 or later.
    public var targetBuildableFolders: Set<String>

    /// Creates `PackageSettings` instance for custom Swift Package Manager configuration.
    /// - Parameters:
    ///     - productTypes: The custom `Product` types to be used for SPM targets.
    ///     - baseProductType: The default product type (usually static framework).
    ///     - productDestinations: Custom destinations to be used for SPM products.
    ///     - baseSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    ///     - expectedSignatures: Expected signatures keyed by binary target name.
    ///     - targetSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    ///     - projectOptions: Custom project configurations to be used for projects generated from SwiftPackageManager.
    ///     - targetBuildableFolders: Targets that should use buildable folders instead of explicit file references.
    public init(
        productTypes: [String: Product] = [:],
        baseProductType: Product = .staticFramework,
        productDestinations: [String: Destinations] = [:],
        baseSettings: Settings = .settings(),
        expectedSignatures: [String: XCFrameworkSignature] = [:],
        targetSettings: [String: Settings] = [:],
        projectOptions: [String: Project.Options] = [:],
        targetBuildableFolders: Set<String> = []
    ) {
        self.productTypes = productTypes
        self.baseProductType = baseProductType
        self.productDestinations = productDestinations
        self.baseSettings = baseSettings
        self.expectedSignatures = expectedSignatures
        self.targetSettings = targetSettings
        self.projectOptions = projectOptions
        self.targetBuildableFolders = targetBuildableFolders
        dumpIfNeeded(self)
    }

    /// Creates `PackageSettings` instance for custom Swift Package Manager configuration.
    /// - Parameters:
    ///     - productTypes: The custom `Product` types to be used for SPM targets.
    ///     - baseProductType: The default product type (usually static framework).
    ///     - productDestinations: Custom destinations to be used for SPM products.
    ///     - baseSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    ///     - expectedSignatures: Expected signatures keyed by binary target name.
    ///     - targetSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    ///     - projectOptions: Custom project configurations to be used for projects generated from SwiftPackageManager.
    @available(
        *,
        deprecated,
        renamed: "init(productTypes:productDestinations:baseSettings:targetSettings:projectOptions:targetBuildableFolders:)",
        message: """
        Consider using the 'Settings' type for parameter 'targetSettings' instead of 'SettingsDictionary'.
        """
    )
    public init(
        productTypes: [String: Product] = [:],
        baseProductType: Product = .staticFramework,
        productDestinations: [String: Destinations] = [:],
        baseSettings: Settings = .settings(),
        expectedSignatures: [String: XCFrameworkSignature] = [:],
        targetSettings: [String: SettingsDictionary],
        projectOptions: [String: Project.Options] = [:],
        targetBuildableFolders: Set<String> = []
    ) {
        self.productTypes = productTypes
        self.baseProductType = baseProductType
        self.productDestinations = productDestinations
        self.baseSettings = baseSettings
        self.expectedSignatures = expectedSignatures
        self.targetSettings = targetSettings.mapValues { .settings(base: $0) }
        self.projectOptions = projectOptions
        self.targetBuildableFolders = targetBuildableFolders
        dumpIfNeeded(self)
    }
}
