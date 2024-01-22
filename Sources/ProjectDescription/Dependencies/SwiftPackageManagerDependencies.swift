import Foundation

public enum PackagesOrManifest: Codable, Equatable {
    case packages([Package])
    case manifest
}

/// A collection of Swift Package Manager dependencies.
///
/// For example, to enabled resource accessors on projects generated from Swift Package Manager:
///
/// ```swift
/// let packageManager = SwiftPackageManagerDependencies(
///     "Package.swift",
///     projectOptions: ["MySwiftPackage":  .options(disableSynthesizedResourceAccessors: false)]
/// )
/// ```
public struct SwiftPackageManagerDependencies: Codable, Equatable {
    /// The path to the `Package.swift` manifest defining the dependencies, or the list of packages that will be installed using
    /// Swift Package Manager.
    public var packagesOrManifest: PackagesOrManifest

    /// The custom `Product` type to be used for SPM targets.
    public var productTypes: [String: Product]

    // The base settings to be used for targets generated from SwiftPackageManager
    public var baseSettings: Settings

    // Additional settings to be added to targets generated from SwiftPackageManager.
    public var targetSettings: [String: SettingsDictionary]

    /// Custom project configurations to be used for projects generated from SwiftPackageManager.
    public var projectOptions: [String: Project.Options]

    /// Creates `SwiftPackageManagerDependencies` instance.
    /// - Parameter packages: List of packages that will be installed using Swift Package Manager.
    /// - Parameter productTypes: The custom `Product` types to be used for SPM targets.
    /// - Parameter baseSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    /// - Parameter targetSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    /// - Parameter projectOptions: Custom project configurations to be used for projects generated from SwiftPackageManager.
    @available(*, deprecated, message: "Use init without packages parameter instead")
    public init(
        _ packages: [Package],
        productTypes: [String: Product] = [:],
        baseSettings: Settings = .settings(),
        targetSettings: [String: SettingsDictionary] = [:],
        projectOptions: [String: Project.Options] = [:]
    ) {
        packagesOrManifest = .packages(packages)
        self.productTypes = productTypes
        self.baseSettings = baseSettings
        self.targetSettings = targetSettings
        self.projectOptions = projectOptions
    }

    /// Creates `SwiftPackageManagerDependencies` instance using the package manifest at `Tuist/Package.swift`.
    /// - Parameter productTypes: The custom `Product` types to be used for SPM targets.
    /// - Parameter baseSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    /// - Parameter targetSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    /// - Parameter projectOptions: Custom project configurations to be used for projects generated from SwiftPackageManager.
    public init(
        productTypes: [String: Product] = [:],
        baseSettings: Settings = .settings(),
        targetSettings: [String: SettingsDictionary] = [:],
        projectOptions: [String: Project.Options] = [:]
    ) {
        packagesOrManifest = .manifest
        self.productTypes = productTypes
        self.baseSettings = baseSettings
        self.targetSettings = targetSettings
        self.projectOptions = projectOptions
    }
}
