import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.SwiftPackageManagerDependencies {
    /// Creates `TuistGraph.SwiftPackageManagerDependencies` instance from `ProjectDescription.SwiftPackageManagerDependencies`
    /// instance.
    static func from(
        manifest: ProjectDescription.SwiftPackageManagerDependencies,
        generatorPaths: GeneratorPaths
    ) throws -> Self {
        let packagesOrManifestPath: TuistGraph.PackagesOrManifestPath
        switch manifest.packagesOrManifestPath {
        case .packages(let packages):
            packagesOrManifestPath = .packages(try packages.map { try TuistGraph.Package.from(manifest: $0, generatorPaths: generatorPaths) })
        case .manifest(let path):
            packagesOrManifestPath = .manifest(try generatorPaths.resolve(path: path))
        }
        let productTypes = manifest.productTypes.mapValues { TuistGraph.Product.from(manifest: $0) }
        let baseSettings = try TuistGraph.Settings.from(manifest: manifest.baseSettings, generatorPaths: generatorPaths)
        let targetSettings = manifest.targetSettings.mapValues { TuistGraph.SettingsDictionary.from(manifest: $0) }
        let projectOptions: [String: TuistGraph.Project.Options] = manifest
            .projectOptions
            .mapValues { .from(manifest: $0) }

        return .init(
            packagesOrManifestPath,
            productTypes: productTypes,
            baseSettings: baseSettings,
            targetSettings: targetSettings,
            projectOptions: projectOptions
        )
    }
}
