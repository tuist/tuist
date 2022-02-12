import Foundation
import ProjectDescription
import TSCBasic
import TuistGraph

extension TuistGraph.ProfileAction {
    static func from(
        manifest: ProjectDescription.ProfileAction,
        generatorPaths: GeneratorPaths
    ) throws -> TuistGraph.ProfileAction {
        let configurationName = manifest.configuration.rawValue

        let preActions = try manifest.preActions.map {
            try TuistGraph.ExecutionAction.from(
                manifest: $0,
                generatorPaths: generatorPaths
            )
        }

        let postActions = try manifest.postActions.map {
            try TuistGraph.ExecutionAction.from(
                manifest: $0,
                generatorPaths: generatorPaths
            )
        }

        let arguments = manifest.arguments.map { TuistGraph.Arguments.from(manifest: $0) }

        var executableResolved: TuistGraph.TargetReference?
        if let executable = manifest.executable {
            executableResolved = TargetReference(
                projectPath: try generatorPaths.resolveSchemeActionProjectPath(executable.projectPath),
                name: executable.targetName
            )
        }

        return ProfileAction(
            configurationName: configurationName,
            preActions: preActions,
            postActions: postActions,
            executable: executableResolved,
            arguments: arguments
        )
    }
}
