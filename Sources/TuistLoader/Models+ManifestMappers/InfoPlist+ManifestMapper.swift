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
                dictionary.mapValues { TuistGraph.PList.Value.from(manifest: $0) }
            )
        case let .extendingDefault(dictionary):
            return .extendingDefault(
                with:
                dictionary.mapValues { TuistGraph.PList.Value.from(manifest: $0) }
            )
        case .none:
            return .none
        }
    }
}

extension TuistGraph.Entitlements {
    /// Maps a ProjectDescription.Entitlements instance into a TuistGraph.Entitlements instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the entitlements model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Entitlements?, generatorPaths: GeneratorPaths) throws -> TuistGraph.Entitlements? {
        switch manifest {
        case let .file(infoplistPath):
            return .file(path: try generatorPaths.resolve(path: infoplistPath))
        case let .dictionary(dictionary):
            return .dictionary(
                dictionary.mapValues { TuistGraph.PList.Value.from(manifest: $0) }
            )
        case .none:
            return .none
        }
    }
}

extension TuistGraph.PList.Value {
    /// Maps a ProjectDescription.PList.Value instance into a TuistGraph.PList.Value instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the Info plist value model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.PList.Value) -> TuistGraph.PList.Value {
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
            return .array(value.map { TuistGraph.PList.Value.from(manifest: $0) })
        case let .dictionary(value):
            return .dictionary(value.mapValues { TuistGraph.PList.Value.from(manifest: $0) })
        }
    }
}
