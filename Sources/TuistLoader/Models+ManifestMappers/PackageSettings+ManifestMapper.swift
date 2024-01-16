import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import TSCUtility

extension TuistGraph.PackageSettings {
    /// Creates `TuistGraph.PackageSettings` instance from `ProjectDescription.PackageSettings`
    /// instance.
    static func from(
        manifest: ProjectDescription.PackageSettings,
        generatorPaths: GeneratorPaths,
        swiftToolsVersion: TSCUtility.Version
    ) throws -> Self {
        let productTypes = manifest.productTypes.mapValues { TuistGraph.Product.from(manifest: $0) }
        let baseSettings = try TuistGraph.Settings.from(manifest: manifest.baseSettings, generatorPaths: generatorPaths)
        let targetSettings = manifest.targetSettings.mapValues { TuistGraph.SettingsDictionary.from(manifest: $0) }
        let projectOptions: [String: TuistGraph.Project.Options] = manifest
            .projectOptions
            .mapValues { .from(manifest: $0) }
        let platforms = try Set(manifest.platforms.map { try TuistGraph.PackagePlatform.from(manifest: $0) })

        return .init(
            productTypes: productTypes,
            baseSettings: baseSettings,
            targetSettings: targetSettings,
            projectOptions: projectOptions,
            swiftToolsVersion: swiftToolsVersion,
            platforms: platforms
        )
    }
}
