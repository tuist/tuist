import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.TuistConfig: ModelConvertible {
    init(manifest: ProjectDescription.TuistConfig, path: AbsolutePath) throws {
        let generationOptions = try manifest.generationOptions.map { try TuistCore.TuistConfig.GenerationOptions(manifest: $0, path: path) }
        let compatibleXcodeVersions = try TuistCore.CompatibleXcodeVersions(manifest: manifest.compatibleXcodeVersions, path: path)
        self.init(compatibleXcodeVersions: compatibleXcodeVersions, generationOptions: generationOptions)
    }
}

extension TuistCore.TuistConfig.GenerationOptions: ModelConvertible {
    init(manifest: ProjectDescription.TuistConfig.GenerationOptions, path _: AbsolutePath) throws {
        switch manifest {
        case let .xcodeProjectName(templateString):
            self = .xcodeProjectName(templateString.description)
        }
    }
}
