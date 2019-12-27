import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.InfoPlist: ModelConvertible {
    init(manifest: ProjectDescription.InfoPlist, generatorPaths: GeneratorPaths) throws {
        switch manifest {
        case let .file(infoplistPath):
            self = .file(path: try generatorPaths.resolve(path: infoplistPath))
        case let .dictionary(dictionary):
            self = try .dictionary(
                dictionary.mapValues { try TuistCore.InfoPlist.Value(manifest: $0, generatorPaths: generatorPaths) }
            )
        case let .extendingDefault(dictionary):
            self = try .extendingDefault(with:
                dictionary.mapValues { try TuistCore.InfoPlist.Value(manifest: $0, generatorPaths: generatorPaths) })
        }
    }
}

extension TuistCore.InfoPlist.Value: ModelConvertible {
    init(manifest: ProjectDescription.InfoPlist.Value, generatorPaths: GeneratorPaths) throws {
        switch manifest {
        case let .string(value):
            self = .string(value)
        case let .boolean(value):
            self = .boolean(value)
        case let .integer(value):
            self = .integer(value)
        case let .array(value):
            self = try .array(value.map { try TuistCore.InfoPlist.Value(manifest: $0, generatorPaths: generatorPaths) })
        case let .dictionary(value):
            self = try .dictionary(value.mapValues { try TuistCore.InfoPlist.Value(manifest: $0, generatorPaths: generatorPaths) })
        }
    }
}
