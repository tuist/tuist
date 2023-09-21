import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.InfoPlist {
    /// Maps a ProjectDescription.InfoPlist instance into a TuistGraph.InfoPlist instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the Info plist model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.InfoPlist?, generatorPaths: GeneratorPaths) throws -> TuistGraph.InfoPlist? {
        switch manifest {
        case let .file(infoplistPath):
            return .file(path: try generatorPaths.resolve(path: infoplistPath))
        case let .dictionary(dictionary):
            return .dictionary(
                dictionary.mapValues { TuistGraph.Plist.Value.from(manifest: $0) }
            )
        case let .extendingDefault(dictionary):
            return .extendingDefault(
                with:
                dictionary.mapValues { TuistGraph.Plist.Value.from(manifest: $0) }
            )
        case .none:
            return .none
        }
    }
}
