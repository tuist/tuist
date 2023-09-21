import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.Entitlements {
    /// Maps a ProjectDescription.Entitlements instance into a TuistGraph.Entitlements instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the Entitlements model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Entitlements?, generatorPaths: GeneratorPaths) throws -> TuistGraph
        .Entitlements?
    {
        switch manifest {
        case let .file(infoplistPath):
            return .file(path: try generatorPaths.resolve(path: infoplistPath))
        case let .dictionary(dictionary):
            return .dictionary(
                dictionary.mapValues { TuistGraph.Plist.Value.from(manifest: $0) }
            )
        case .none:
            return .none
        }
    }
}
