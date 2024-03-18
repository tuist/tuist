import Foundation
import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.PackageSettings {
    /// Creates `TuistGraph.PackageSettings` instance from `ProjectDescription.PackageSettings`
    /// instance.
    static func from(
        manifest: ProjectDescription.PackageSettings,
        generatorPaths: GeneratorPaths,
        swiftToolsVersion: TSCUtility.Version
    ) throws -> Self {
        let productTypes = manifest.productTypes.mapValues { TuistGraph.Product.from(manifest: $0) }
        let productDestinations = try manifest.productDestinations.mapValues { try TuistGraph.Destination.from(destinations: $0) }
        let baseSettings = try TuistGraph.Settings.from(manifest: manifest.baseSettings, generatorPaths: generatorPaths)
        let targetSettings = manifest.targetSettings.mapValues { TuistGraph.SettingsDictionary.from(manifest: $0) }
        let projectOptions: [String: TuistGraph.Project.Options] = manifest
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
