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
     SPM tries to make linking work by making build-time decisions like how to link packages on behalf of users.
     While this is desirable at a small scale (it's convenient), we believe it's not a good idea at a large scale because it might
     cause issues like duplicated symbols or increased binary size.

     We believe that how things are linked is something that Xcode project maintainers should think about, with Tuist helping
     with any complexities associated with it, but we acknowledge the interest of some of our users to align with SPM's convenient
     behaviour, and therefore we include this flag for users to opt-into that behaviour.

     Here are some things that we do as part of that.

     - We set the `GENERATE_MASTER_OBJECT_FILE` build setting in static targets by default (https://github.com/apple/swift/issues/48561)
     */
    public var spmLinkingStyle: Bool

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
    ///     - spmLinkingStyle: When `true`, it mimics SPM's linking style.
    /// targets.
    public init(
        productTypes: [String: Product] = [:],
        productDestinations: [String: Destinations] = [:],
        baseSettings: Settings = .settings(),
        targetSettings: [String: SettingsDictionary] = [:],
        projectOptions: [String: Project.Options] = [:],
        spmLinkingStyle: Bool = false
    ) {
        self.productTypes = productTypes
        self.productDestinations = productDestinations
        self.baseSettings = baseSettings
        self.targetSettings = targetSettings
        self.projectOptions = projectOptions
        self.spmLinkingStyle = spmLinkingStyle
        dumpIfNeeded(self)
    }
}
