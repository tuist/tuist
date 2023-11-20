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
        let packagesOrManifest: TuistGraph.PackagesOrManifest
        switch manifest.packagesOrManifest {
        case let .packages(packages):
            packagesOrManifest = .packages(try packages.map { try TuistGraph.Package.from(
                manifest: $0,
                generatorPaths: generatorPaths
            ) })
        case .manifest:
            let packageSwiftPath = generatorPaths.manifestDirectory.appending(components: [
                Constants.tuistDirectoryName,
                Constants.DependenciesDirectory.packageSwiftName,
            ])
            packagesOrManifest = .manifest(packageSwiftPath)
        }
        let productTypes = manifest.productTypes.mapValues { TuistGraph.Product.from(manifest: $0) }
        let baseSettings = try TuistGraph.Settings.from(manifest: manifest.baseSettings, generatorPaths: generatorPaths)
        let targetSettings = manifest.targetSettings.mapValues { TuistGraph.SettingsDictionary.from(manifest: $0) }
        let projectOptions: [String: TuistGraph.Project.Options] = manifest
            .projectOptions
            .mapValues { .from(manifest: $0) }

        return .init(
            packagesOrManifest,
            productTypes: productTypes,
            baseSettings: baseSettings,
            targetSettings: targetSettings,
            projectOptions: projectOptions
        )
    }
}
