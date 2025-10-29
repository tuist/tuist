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
        let productTraits = Dictionary(uniqueKeysWithValues: manifest.productTraits.map { productName, traits in
            let mappedTraits = traits.map { trait -> TuistCore.PackageSettingsTrait in
                switch trait {
                case .default: return .default
                case let .named(name): return .named(name)
                @unknown default:
                    fatalError("Invalid trait type")
                }
            }
            return (productName, mappedTraits)
        })

        return .init(
            productTypes: productTypes,
            productDestinations: productDestinations,
            baseSettings: baseSettings,
            targetSettings: targetSettings,
            projectOptions: projectOptions,
            productTraits: productTraits
        )
    }
}
