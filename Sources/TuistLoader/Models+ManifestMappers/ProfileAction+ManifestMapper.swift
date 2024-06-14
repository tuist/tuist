import Foundation
import Path
import ProjectDescription
import XcodeGraph

extension XcodeGraph.ProfileAction {
    static func from(
        manifest: ProjectDescription.ProfileAction,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeGraph.ProfileAction {
        let configurationName = manifest.configuration.rawValue

        let preActions = try manifest.preActions.map {
            try XcodeGraph.ExecutionAction.from(
                manifest: $0,
                generatorPaths: generatorPaths
            )
        }

        let postActions = try manifest.postActions.map {
            try XcodeGraph.ExecutionAction.from(
                manifest: $0,
                generatorPaths: generatorPaths
            )
        }

        let arguments = manifest.arguments.map { XcodeGraph.Arguments.from(manifest: $0) }

        var executableResolved: XcodeGraph.TargetReference?
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
