import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.AnalyzeAction {
    static func from(
        manifest: ProjectDescription.AnalyzeAction,
        generatorPaths _: GeneratorPaths
    ) throws -> TuistGraph.AnalyzeAction {
        let configurationName = manifest.configuration.rawValue

        return AnalyzeAction(configurationName: configurationName)
    }
}
