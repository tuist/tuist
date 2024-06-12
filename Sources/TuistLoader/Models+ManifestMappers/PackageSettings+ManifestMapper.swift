import Foundation
import Path
import ProjectDescription
import TSCUtility
import TuistCore
import TuistSupport
import XcodeGraph

extension TuistCore.PackageSettings {
    /// Creates `XcodeGraph.PackageSettings` instance from `ProjectDescription.PackageSettings`
    /// instance.
    static func from(
        manifest: ProjectDescription.PackageSettings,
        generatorPaths: GeneratorPaths,
        swiftToolsVersion: TSCUtility.Version
    ) throws -> Self {
        let productTypes = manifest.productTypes.mapValues { XcodeGraph.Product.from(manifest: $0) }
        let productDestinations = try manifest.productDestinations.mapValues { try XcodeGraph.Destination.from(destinations: $0) }
        let baseSettings = try XcodeGraph.Settings.from(manifest: manifest.baseSettings, generatorPaths: generatorPaths)
        let targetSettings = manifest.targetSettings.mapValues { XcodeGraph.SettingsDictionary.from(manifest: $0) }
        let projectOptions: [String: XcodeGraph.Project.Options] = manifest
            .projectOptions
            .mapValues { .from(manifest: $0) }

        return .init(
            productTypes: productTypes,
            productDestinations: productDestinations,
            baseSettings: baseSettings,
            targetSettings: targetSettings,
            projectOptions: projectOptions,
            swiftToolsVersion: .init(stringLiteral: swiftToolsVersion.description)
        )
    }
}
