import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.TuistConfig {
    static func from(manifest: ProjectDescription.TuistConfig,
                     path _: AbsolutePath) throws -> TuistCore.TuistConfig {
        let generationOptions = try manifest.generationOptions.map { try TuistCore.TuistConfig.GenerationOption.from(manifest: $0) }
        let compatibleXcodeVersions = TuistCore.CompatibleXcodeVersions.from(manifest: manifest.compatibleXcodeVersions)

        return TuistCore.TuistConfig(compatibleXcodeVersions: compatibleXcodeVersions,
                                     generationOptions: generationOptions)
    }
}
