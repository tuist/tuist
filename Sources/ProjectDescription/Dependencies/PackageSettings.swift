import Foundation

/// A custom Swift Package Manager configuration
///
///
/// ```swift
/// // swift-tools-version: 5.8
/// import PackageDescription
///
/// #if TUIST
///     import ProjectDescription
///     import ProjectDescriptionHelpers
///
///     let packageSettings = PackageSettings(
///         productTypes: [
///             "Alamofire": .framework, // default is .staticFramework
///         ],
///         platforms: [.iOS]
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

    // The base settings to be used for targets generated from SwiftPackageManager
    public var baseSettings: Settings

    // Additional settings to be added to targets generated from SwiftPackageManager.
    public var targetSettings: [String: SettingsDictionary]

    /// Custom project configurations to be used for projects generated from SwiftPackageManager.
    public var projectOptions: [String: Project.Options]

    /// The custom set of `platforms` that are used by your project
    public let platforms: Set<PackagePlatform>

    /// Creates `PackageSettings` instance for custom Swift Package Manager configuration.
    /// - Parameter productTypes: The custom `Product` types to be used for SPM targets.
    /// - Parameter baseSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    /// - Parameter targetSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    /// - Parameter projectOptions: Custom project configurations to be used for projects generated from SwiftPackageManager.
    /// - Parameter platforms: The custom set of `platforms` that are used by your project
    public init(
        productTypes: [String: Product] = [:],
        baseSettings: Settings = .settings(),
        targetSettings: [String: SettingsDictionary] = [:],
        projectOptions: [String: Project.Options] = [:],
        platforms: Set<PackagePlatform> = Set(PackagePlatform.allCases)
    ) {
        self.productTypes = productTypes
        self.baseSettings = baseSettings
        self.targetSettings = targetSettings
        self.projectOptions = projectOptions
        self.platforms = platforms
        dumpIfNeeded(self)
    }
}
