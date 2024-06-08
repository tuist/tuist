import Foundation
import Path
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.Entitlements {
    /// Maps a ProjectDescription.Entitlements instance into a XcodeGraph.Entitlements instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the Entitlements model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Entitlements?, generatorPaths: GeneratorPaths) throws -> XcodeGraph
        .Entitlements?
    {
        switch manifest {
        case let .file(infoplistPath):
            return .file(path: try generatorPaths.resolve(path: infoplistPath))
        case let .dictionary(dictionary):
            return .dictionary(
                dictionary.mapValues { XcodeGraph.Plist.Value.from(manifest: $0) }
            )
        case let .variable(setting):
            return .variable(setting)
        case .none:
            return .none
        }
    }
}
