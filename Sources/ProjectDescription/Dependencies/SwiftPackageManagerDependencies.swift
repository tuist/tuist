import Foundation

public enum PackagesOrManifestPath: Codable, Equatable {
    case packages([Package])
    case manifest(Path)
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
    public let packagesOrManifestPath: PackagesOrManifestPath

    /// The custom `Product` type to be used for SPM targets.
    public let productTypes: [String: Product]

    // The base settings to be used for targets generated from SwiftPackageManager
    public let baseSettings: Settings

    // Additional settings to be added to targets generated from SwiftPackageManager.
    public let targetSettings: [String: SettingsDictionary]

    /// Custom project configurations to be used for projects generated from SwiftPackageManager.
    public let projectOptions: [String: ProjectDescription.Project.Options]

    /// Creates `SwiftPackageManagerDependencies` instance.
    /// - Parameter packages: List of packages that will be installed using Swift Package Manager.
    /// - Parameter productTypes: The custom `Product` types to be used for SPM targets.
    /// - Parameter baseSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    /// - Parameter targetSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    /// - Parameter projectOptions: Custom project configurations to be used for projects generated from SwiftPackageManager.
    @available(*, deprecated, message: "Use init with manifest path instead")
    public init(
        _ packages: [Package],
        productTypes: [String: Product] = [:],
        baseSettings: Settings = .settings(),
        targetSettings: [String: SettingsDictionary] = [:],
        projectOptions: [String: ProjectDescription.Project.Options] = [:]
    ) {
        self.init(
            packagesOrManifestPath: .packages(packages),
            productTypes: productTypes,
            baseSettings: baseSettings,
            targetSettings: targetSettings,
            projectOptions: projectOptions
        )
    }

    /// Creates `SwiftPackageManagerDependencies` instance.
    /// - Parameter manifest: The path to the `Package.swift` manifest defining the dependencies.
    /// - Parameter productTypes: The custom `Product` types to be used for SPM targets.
    /// - Parameter baseSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    /// - Parameter targetSettings: Additional settings to be added to targets generated from SwiftPackageManager.
    /// - Parameter projectOptions: Custom project configurations to be used for projects generated from SwiftPackageManager.
    public init(
        manifest: Path = "Package.swift",
        productTypes: [String: Product] = [:],
        baseSettings: Settings = .settings(),
        targetSettings: [String: SettingsDictionary] = [:],
        projectOptions: [String: ProjectDescription.Project.Options] = [:]
    ) {
        self.init(
            packagesOrManifestPath: .manifest(manifest),
            productTypes: productTypes,
            baseSettings: baseSettings,
            targetSettings: targetSettings,
            projectOptions: projectOptions
        )
    }

    private init(
        packagesOrManifestPath: PackagesOrManifestPath,
        productTypes: [String: Product],
        baseSettings: Settings,
        targetSettings: [String: SettingsDictionary],
        projectOptions: [String: ProjectDescription.Project.Options]
    ) {
        self.packagesOrManifestPath = packagesOrManifestPath
        self.productTypes = productTypes
        self.baseSettings = baseSettings
        self.targetSettings = targetSettings
        self.projectOptions = projectOptions
    }
}

// MARK: - ExpressibleByArrayLiteral

extension SwiftPackageManagerDependencies: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Package...) {
        self.init(
            packagesOrManifestPath: .packages(elements),
            productTypes: [:],
            baseSettings: .settings(),
            targetSettings: [:],
            projectOptions: [:]
        )
    }
}
