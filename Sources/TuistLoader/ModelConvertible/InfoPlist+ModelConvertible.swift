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
            self = .dictionary(
                dictionary.mapValues { TuistCore.InfoPlist.Value.from(manifest: $0) }
            )
        case let .extendingDefault(dictionary):
            self = .extendingDefault(with:
                dictionary.mapValues { TuistCore.InfoPlist.Value.from(manifest: $0) })
        }
    }
}
