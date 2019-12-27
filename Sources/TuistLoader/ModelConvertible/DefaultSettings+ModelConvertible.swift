import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.DefaultSettings: ModelConvertible {
    init(manifest: ProjectDescription.DefaultSettings, generatorPaths _: GeneratorPaths) throws {
        switch manifest {
        case .recommended:
            self = .recommended
        case .essential:
            self = .essential
        case .none:
            self = .none
        }
    }
}
