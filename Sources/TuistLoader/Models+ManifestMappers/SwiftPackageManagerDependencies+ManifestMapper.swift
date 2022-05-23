import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.SwiftPackageManagerDependencies {
    /// Creates `TuistGraph.SwiftPackageManagerDependencies` instance from `ProjectDescription.SwiftPackageManagerDependencies` instance.
    static func from(
        manifest: ProjectDescription.SwiftPackageManagerDependencies,
        generatorPaths: GeneratorPaths,
        plugins: Plugins,
        resourceSynthesizerPathLocator: ResourceSynthesizerPathLocating
    ) throws -> Self {
        let packages = try manifest.packages.map { try TuistGraph.Package.from(manifest: $0, generatorPaths: generatorPaths) }
        let productTypes = manifest.productTypes.mapValues { TuistGraph.Product.from(manifest: $0) }
        let baseSettings = try TuistGraph.Settings.from(manifest: manifest.baseSettings, generatorPaths: generatorPaths)
        let targetSettings = manifest.targetSettings.mapValues { TuistGraph.SettingsDictionary.from(manifest: $0) }
        let options = TuistGraph.Project.Options.from(manifest: manifest.options)
        let resourceSynthesizers = try manifest.resourceSynthesizers.map {
            try TuistGraph.ResourceSynthesizer.from(
                manifest: $0,
                generatorPaths: generatorPaths,
                plugins: plugins,
                resourceSynthesizerPathLocator: resourceSynthesizerPathLocator
            )
        }

        return .init(
            packages,
            productTypes: productTypes,
            baseSettings: baseSettings,
            targetSettings: targetSettings,
            options: options,
            resourceSynthesizers: resourceSynthesizers
        )
    }
}
