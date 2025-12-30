import Foundation
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
        generatorPaths: GeneratorPaths
    ) throws -> Self {
        let productTypes = manifest.productTypes.mapValues { XcodeGraph.Product.from(manifest: $0) }
        let productDestinations = try manifest.productDestinations.mapValues { try XcodeGraph.Destination.from(destinations: $0) }
        let baseSettings = try XcodeGraph.Settings.from(manifest: manifest.baseSettings, generatorPaths: generatorPaths)
        let targetSettings = try manifest.targetSettings.mapValues { try XcodeGraph.Settings.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let projectOptions: [String: XcodeGraph.Project.Options] = manifest
            .projectOptions
            .mapValues { .from(manifest: $0) }

        return .init(
            productTypes: productTypes,
            productDestinations: productDestinations,
            baseSettings: baseSettings,
            targetSettings: targetSettings,
            projectOptions: projectOptions
        )
    }
}
