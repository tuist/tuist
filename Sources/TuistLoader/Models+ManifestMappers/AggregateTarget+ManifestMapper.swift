import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.Target {
    /// Maps a ProjectDescription.AggregateTarget instance into a TuistGraph.Target instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the aggregate target.
    ///   - generatorPaths: Generator paths.
    ///   - externalDependencies: External dependencies graph.
    static func from(
        manifest: ProjectDescription.AggregateTarget,
        generatorPaths: GeneratorPaths,
        externalDependencies _: [TuistGraph.Platform: [String: [TuistGraph.TargetDependency]]]
    ) throws -> TuistGraph.Target {
        let platform = try TuistGraph.Platform.from(manifest: manifest.platform)
        let settings = try manifest.settings.map { try TuistGraph.Settings.from(manifest: $0, generatorPaths: generatorPaths) }
        let scripts = try manifest.scripts.map {
            try TuistGraph.TargetScript.from(manifest: $0, generatorPaths: generatorPaths)
        }

        return TuistGraph.Target(
            name: manifest.name,
            platform: platform,
            product: .aggregateTarget,
            productName: nil,
            bundleId: "",
            settings: settings,
            scripts: scripts,
            filesGroup: .group(name: "Project")
        )
    }
}
