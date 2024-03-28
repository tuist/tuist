import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.PrivacyManifest {
    /// Maps a ProjectDescription.PrivacyManifest instance into a TuistGraph.PrivacyManifest instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the PrivacyManifest model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.PrivacyManifest?, generatorPaths: GeneratorPaths) throws -> TuistGraph
        .PrivacyManifest?
    {
        switch manifest {
        case let .file(privacyManifestPath):
            return .file(path: try generatorPaths.resolve(path: privacyManifestPath))
        case let .dictionary(dictionary):
            return .dictionary(
                dictionary.mapValues { TuistGraph.Plist.Value.from(manifest: $0) }
            )
        case .none:
            return .none
        }
    }
}
