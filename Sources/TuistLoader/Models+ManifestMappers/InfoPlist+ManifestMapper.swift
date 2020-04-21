import Foundation
import ProjectDescription
import TSCBasic
import TuistCore

extension TuistCore.InfoPlist {
    /// Maps a ProjectDescription.InfoPlist instance into a TuistCore.InfoPlist instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the Info plist model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.InfoPlist, generatorPaths: GeneratorPaths) throws -> TuistCore.InfoPlist {
        switch manifest {
        case let .file(infoplistPath):
            return .file(path: try generatorPaths.resolve(path: infoplistPath))
        case let .dictionary(dictionary):
            return .dictionary(
                dictionary.mapValues { TuistCore.InfoPlist.Value.from(manifest: $0) }
            )
        case let .extendingDefault(dictionary):
            return .extendingDefault(with:
                dictionary.mapValues { TuistCore.InfoPlist.Value.from(manifest: $0) })
        }
    }
}

extension TuistCore.InfoPlist.Value {
    /// Maps a ProjectDescription.InfoPlist.Value instance into a TuistCore.InfoPlist.Value instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the Info plist value model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.InfoPlist.Value) -> TuistCore.InfoPlist.Value {
        switch manifest {
        case let .string(value):
            return .string(value)
        case let .boolean(value):
            return .boolean(value)
        case let .integer(value):
            return .integer(value)
        case let .array(value):
            return .array(value.map { TuistCore.InfoPlist.Value.from(manifest: $0) })
        case let .dictionary(value):
            return .dictionary(value.mapValues { TuistCore.InfoPlist.Value.from(manifest: $0) })
        }
    }
}
