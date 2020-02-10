import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.TuistConfig.GenerationOption {
    static func from(manifest: ProjectDescription.TuistConfig.GenerationOptions) throws -> TuistCore.TuistConfig.GenerationOption {
        switch manifest {
        case let .xcodeProjectName(templateString):
            return .xcodeProjectName(templateString.description)
        }
    }
}
