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
    static func from(manifest: ProjectDescription.InfoPlist, generatorPaths: GeneratorPaths) throws -> TuistGraph.InfoPlist {
        switch manifest {
        case let .file(infoplistPath):
            return .file(path: try generatorPaths.resolve(path: infoplistPath))
        case let .dictionary(dictionary):
            return .dictionary(
                dictionary.mapValues { TuistGraph.InfoPlist.Value.from(manifest: $0) }
            )
        case let .extendingDefault(dictionary):
            return .extendingDefault(
                with:
                dictionary.mapValues { TuistGraph.InfoPlist.Value.from(manifest: $0) }
            )
        }
    }
}

extension TuistGraph.InfoPlist.Value {
    /// Maps a ProjectDescription.InfoPlist.Value instance into a TuistGraph.InfoPlist.Value instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the Info plist value model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.InfoPlist.Value) -> TuistGraph.InfoPlist.Value {
        switch manifest {
        case let .string(value):
            return .string(value)
        case let .boolean(value):
            return .boolean(value)
        case let .integer(value):
            return .integer(value)
        case let .real(value):
            return .real(value)
        case let .array(value):
            return .array(value.map { TuistGraph.InfoPlist.Value.from(manifest: $0) })
        case let .dictionary(value):
            return .dictionary(value.mapValues { TuistGraph.InfoPlist.Value.from(manifest: $0) })
        }
    }
}
