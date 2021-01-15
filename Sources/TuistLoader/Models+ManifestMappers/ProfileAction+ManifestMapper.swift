import Foundation
import ProjectDescription
import TSCBasic
import TuistGraph

extension TuistGraph.ProfileAction {
    static func from(manifest: ProjectDescription.ProfileAction,
                     generatorPaths: GeneratorPaths) throws -> TuistGraph.ProfileAction
    {
        let configurationName = manifest.configurationName
        let arguments = manifest.arguments.map { TuistGraph.Arguments.from(manifest: $0) }

        var executableResolved: TuistGraph.TargetReference?
        if let executable = manifest.executable {
            executableResolved = TargetReference(projectPath: try generatorPaths.resolveSchemeActionProjectPath(executable.projectPath),
                                                 name: executable.targetName)
        }

        return ProfileAction(configurationName: configurationName,
                             executable: executableResolved,
                             arguments: arguments)
    }
}
