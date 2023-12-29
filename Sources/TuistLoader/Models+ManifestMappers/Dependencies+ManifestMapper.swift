import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.Dependencies {
    /// Creates `TuistGraph.Dependencies` instance from `ProjectDescription.Dependencies`
    /// instance.
    static func from(
        manifest: ProjectDescription.Dependencies,
        generatorPaths: GeneratorPaths
    ) throws -> Self {
        let package = try manifest.package.map { try generatorPaths.resolve(path: $0) }
        let productTypes = manifest.productTypes.mapValues { TuistGraph.Product.from(manifest: $0) }
        let baseSettings = try TuistGraph.Settings.from(manifest: manifest.baseSettings, generatorPaths: generatorPaths)
        let targetSettings = manifest.targetSettings.mapValues { TuistGraph.SettingsDictionary.from(manifest: $0) }
        let projectOptions: [String: TuistGraph.Project.Options] = manifest
            .projectOptions
            .mapValues { .from(manifest: $0) }

        return .init(
            package: package,
            productTypes: productTypes,
            baseSettings: baseSettings,
            targetSettings: targetSettings,
            projectOptions: projectOptions
        )
    }
}
