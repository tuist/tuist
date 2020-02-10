import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.TuistConfig {
    /// Maps a ProjectDescription.TuistConfig instance into a TuistCore.TuistConfig model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.TuistConfig) throws -> TuistCore.TuistConfig {
        let generationOptions = try manifest.generationOptions.map { try TuistCore.TuistConfig.GenerationOption.from(manifest: $0) }
        let compatibleXcodeVersions = TuistCore.CompatibleXcodeVersions.from(manifest: manifest.compatibleXcodeVersions)

        return TuistCore.TuistConfig(compatibleXcodeVersions: compatibleXcodeVersions,
                                     generationOptions: generationOptions)
    }
}

extension TuistCore.TuistConfig.GenerationOption {
    /// Maps a ProjectDescription.TuistConfig.GenerationOptions instance into a TuistCore.TuistConfig.GenerationOptions model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config generation options
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.TuistConfig.GenerationOptions) throws -> TuistCore.TuistConfig.GenerationOption {
        switch manifest {
        case let .xcodeProjectName(templateString):
            return .xcodeProjectName(templateString.description)
        }
    }
}
