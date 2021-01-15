import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.AnalyzeAction {
    static func from(manifest: ProjectDescription.AnalyzeAction,
                     generatorPaths _: GeneratorPaths) throws -> TuistCore.AnalyzeAction
    {
        let configurationName = manifest.configurationName

        return AnalyzeAction(configurationName: configurationName)
    }
}
