import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.SDKStatus: ModelConvertible {
    init(manifest: ProjectDescription.SDKStatus, generatorPaths _: GeneratorPaths) throws {
        switch manifest {
        case .required:
            self = .required
        case .optional:
            self = .optional
        }
    }
}
