import Foundation
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.InfoPlist {
    /// Maps a ProjectDescription.InfoPlist instance into a XcodeGraph.InfoPlist instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the Info plist model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.InfoPlist?, generatorPaths: GeneratorPaths) throws -> XcodeGraph.InfoPlist? {
        switch manifest {
        case let .file(infoplistPath):
            return .file(path: try generatorPaths.resolve(path: infoplistPath))
        case let .dictionary(dictionary):
            return .dictionary(
                dictionary.mapValues { XcodeGraph.Plist.Value.from(manifest: $0) }
            )
        case let .extendingDefault(dictionary):
            return .extendingDefault(
                with:
                dictionary.mapValues { XcodeGraph.Plist.Value.from(manifest: $0) }
            )
        case let .extendingFile(infoplistPath, dictionary):
            let resolvedPath = try generatorPaths.resolve(path: infoplistPath)
            let resolvedDictionary = dictionary.mapValues { XcodeGraph.Plist.Value.from(manifest: $0) }
            return .extendingFile(path: resolvedPath, with: resolvedDictionary)
        case .none:
            return .none
        }
    }
}
