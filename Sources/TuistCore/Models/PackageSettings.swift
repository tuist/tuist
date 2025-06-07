import Foundation
import XcodeGraph

/// Contains the description of custom SPM settings
public struct PackageSettings: Equatable, Codable {
    /// The custom `Product` types to be used for SPM targets.
    public let productTypes: [String: Product]

    /// Custom destinations to be used for SPM products.
    public let productDestinations: [String: Destinations]

    /// The base settings to be used for targets generated from SwiftPackageManager.
    public let baseSettings: Settings

    /// The custom `Settings` to be applied to SPM targets.
    public let targetSettings: [String: Settings]

    /// The custom project options for each project generated from a swift package.
    public let projectOptions: [String: XcodeGraph.Project.Options]

    /// Initializes a new `PackageSettings` instance.
    /// - Parameters:
    ///    - productTypes: The custom `Product` types to be used for SPM targets.
    ///    - baseSettings: The base settings to be used for targets generated from SwiftPackageManager
    ///    - targetSettings: The custom `SettingsDictionary` to be applied to denoted targets
    ///    - projectOptions: The custom project options for each project generated from a swift package
    public init(
        productTypes: [String: Product],
        productDestinations: [String: Destinations],
        baseSettings: Settings,
        targetSettings: [String: Settings],
        projectOptions: [String: XcodeGraph.Project.Options] = [:]
    ) {
        self.productTypes = productTypes
        self.productDestinations = productDestinations
        self.baseSettings = baseSettings
        self.targetSettings = targetSettings
        self.projectOptions = projectOptions
    }
}

#if DEBUG
    extension PackageSettings {
        public static func test(
            productTypes: [String: Product] = [:],
            productDestinations: [String: Destinations] = [:],
            baseSettings: Settings = Settings.default,
            targetSettings: [String: Settings] = [:],
            projectOptions: [String: XcodeGraph.Project.Options] = [:]
        ) -> PackageSettings {
            PackageSettings(
                productTypes: productTypes,
                productDestinations: productDestinations,
                baseSettings: baseSettings,
                targetSettings: targetSettings,
                projectOptions: projectOptions
            )
        }
    }
#endif
