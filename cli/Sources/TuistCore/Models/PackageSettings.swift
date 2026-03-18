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

    /// Expected signatures for Swift Package Manager binary targets.
    /// The first-level key is the package name and the second-level key is the binary target name.
    public let binaryTargetSignatures: [String: [String: XCFrameworkSignature]]

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
        binaryTargetSignatures: [String: [String: XCFrameworkSignature]],
        targetSettings: [String: Settings],
        projectOptions: [String: XcodeGraph.Project.Options] = [:]
    ) {
        self.productTypes = productTypes
        self.productDestinations = productDestinations
        self.baseSettings = baseSettings
        self.binaryTargetSignatures = binaryTargetSignatures
        self.targetSettings = targetSettings
        self.projectOptions = projectOptions
    }

    #if DEBUG
        public static func test(
            productTypes: [String: Product] = [:],
            productDestinations: [String: Destinations] = [:],
            baseSettings: Settings = Settings.default,
            binaryTargetSignatures: [String: [String: XCFrameworkSignature]] = [:],
            targetSettings: [String: Settings] = [:],
            projectOptions: [String: XcodeGraph.Project.Options] = [:]
        ) -> PackageSettings {
            PackageSettings(
                productTypes: productTypes,
                productDestinations: productDestinations,
                baseSettings: baseSettings,
                binaryTargetSignatures: binaryTargetSignatures,
                targetSettings: targetSettings,
                projectOptions: projectOptions
            )
        }
    #endif
}
