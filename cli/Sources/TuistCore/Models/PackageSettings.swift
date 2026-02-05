import Foundation
import XcodeGraph
import ProjectDescription

/// Contains the description of custom SPM settings
public struct PackageSettings: Equatable, Codable {
    /// The custom `Product` types to be used for SPM targets.
    public let productTypes: [String: XcodeGraph.Product]

    /// Custom destinations to be used for SPM products.
    public let productDestinations: [String: XcodeGraph.Destinations]

    /// The base settings to be used for targets generated from SwiftPackageManager.
    public let baseSettings: XcodeGraph.Settings

    /// The custom `Settings` to be applied to SPM targets.
    public let targetSettings: [String: XcodeGraph.Settings]

    /// The custom project options for each project generated from a swift package.
    public let projectOptions: [String: XcodeGraph.Project.Options]

    /// The custom resource synthesizers to be used for SPM targets.
    public let resourceSynthesizers: [String: [ProjectDescription.ResourceSynthesizer]]

    /// Initializes a new `PackageSettings` instance.
    /// - Parameters:
    ///    - productTypes: The custom `Product` types to be used for SPM targets.
    ///    - baseSettings: The base settings to be used for targets generated from SwiftPackageManager
    ///    - targetSettings: The custom `SettingsDictionary` to be applied to denoted targets
    ///    - projectOptions: The custom project options for each project generated from a swift package
    ///    - resourceSynthesizers: The custom resource synthesizers to be used for SPM targets
    public init(
        productTypes: [String: XcodeGraph.Product],
        productDestinations: [String: XcodeGraph.Destinations],
        baseSettings: XcodeGraph.Settings,
        targetSettings: [String: XcodeGraph.Settings],
        projectOptions: [String: XcodeGraph.Project.Options] = [:],
        resourceSynthesizers: [String: [ProjectDescription.ResourceSynthesizer]] = [:]
    ) {
        self.productTypes = productTypes
        self.productDestinations = productDestinations
        self.baseSettings = baseSettings
        self.targetSettings = targetSettings
        self.projectOptions = projectOptions
        self.resourceSynthesizers = resourceSynthesizers
    }
}

#if DEBUG
    extension PackageSettings {
        public static func test(
            productTypes: [String: XcodeGraph.Product] = [:],
            productDestinations: [String: XcodeGraph.Destinations] = [:],
            baseSettings: XcodeGraph.Settings = XcodeGraph.Settings.default,
            targetSettings: [String: XcodeGraph.Settings] = [:],
            projectOptions: [String: XcodeGraph.Project.Options] = [:],
            resourceSynthesizers: [String: [ProjectDescription.ResourceSynthesizer]] = [:]
        ) -> PackageSettings {
            PackageSettings(
                productTypes: productTypes,
                productDestinations: productDestinations,
                baseSettings: baseSettings,
                targetSettings: targetSettings,
                projectOptions: projectOptions,
                resourceSynthesizers: resourceSynthesizers
            )
        }
    }
#endif
