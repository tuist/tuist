import Foundation
import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import XcodeProjectGenerator
import TuistSupport

extension XcodeProjectGenerator.PackageSettings {
    /// Creates `XcodeProjectGenerator.PackageSettings` instance from `ProjectDescription.PackageSettings`
    /// instance.
    static func from(
        manifest: ProjectDescription.PackageSettings,
        generatorPaths: GeneratorPaths,
        swiftToolsVersion: TSCUtility.Version
    ) throws -> Self {
        let productTypes = manifest.productTypes.mapValues { XcodeProjectGenerator.Product.from(manifest: $0) }
        let productDestinations = try manifest.productDestinations.mapValues { try XcodeProjectGenerator.Destination.from(destinations: $0) }
        let baseSettings = try XcodeProjectGenerator.Settings.from(manifest: manifest.baseSettings, generatorPaths: generatorPaths)
        let targetSettings = manifest.targetSettings.mapValues { XcodeProjectGenerator.SettingsDictionary.from(manifest: $0) }
        let projectOptions: [String: XcodeProjectGenerator.Project.Options] = manifest
            .projectOptions
            .mapValues { .from(manifest: $0) }

        return .init(
            productTypes: productTypes,
            productDestinations: productDestinations,
            baseSettings: baseSettings,
            targetSettings: targetSettings,
            projectOptions: projectOptions,
            swiftToolsVersion: swiftToolsVersion
        )
    }
}
