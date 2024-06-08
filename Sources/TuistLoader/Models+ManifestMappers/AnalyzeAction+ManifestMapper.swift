import Foundation
import Path
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.AnalyzeAction {
    static func from(
        manifest: ProjectDescription.AnalyzeAction,
        generatorPaths _: GeneratorPaths
    ) throws -> XcodeGraph.AnalyzeAction {
        let configurationName = manifest.configuration.rawValue

        return AnalyzeAction(configurationName: configurationName)
    }
}
