import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.TuistConfig: ModelConvertible {
    init(manifest: ProjectDescription.TuistConfig, generatorPaths: GeneratorPaths) throws {
        let generationOptions = try manifest.generationOptions.map {
            try TuistCore.TuistConfig.GenerationOptions(manifest: $0, generatorPaths: generatorPaths)
        }
        let compatibleXcodeVersions = try TuistCore.CompatibleXcodeVersions(manifest: manifest.compatibleXcodeVersions, generatorPaths: generatorPaths)
        self.init(compatibleXcodeVersions: compatibleXcodeVersions, generationOptions: generationOptions)
    }
}

extension TuistCore.TuistConfig.GenerationOptions: ModelConvertible {
    init(manifest: ProjectDescription.TuistConfig.GenerationOptions, generatorPaths _: GeneratorPaths) throws {
        switch manifest {
        case let .xcodeProjectName(templateString):
            self = .xcodeProjectName(templateString.description)
        }
    }
}
