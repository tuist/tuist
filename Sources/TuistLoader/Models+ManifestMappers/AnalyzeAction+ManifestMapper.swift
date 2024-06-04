import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import XcodeProjectGenerator

extension XcodeProjectGenerator.AnalyzeAction {
    static func from(
        manifest: ProjectDescription.AnalyzeAction,
        generatorPaths _: GeneratorPaths
    ) throws -> XcodeProjectGenerator.AnalyzeAction {
        let configurationName = manifest.configuration.rawValue

        return AnalyzeAction(configurationName: configurationName)
    }
}
