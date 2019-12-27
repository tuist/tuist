import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.SettingValue: ModelConvertible {
    init(manifest: ProjectDescription.SettingValue, generatorPaths _: GeneratorPaths) throws {
        switch manifest {
        case let .string(value):
            self = .string(value)
        case let .array(value):
            self = .array(value)
        }
    }
}
