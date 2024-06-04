import Foundation
import ProjectDescription
import TSCBasic
import XcodeProjectGenerator

extension XcodeProjectGenerator.ProfileAction {
    static func from(
        manifest: ProjectDescription.ProfileAction,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeProjectGenerator.ProfileAction {
        let configurationName = manifest.configuration.rawValue

        let preActions = try manifest.preActions.map {
            try XcodeProjectGenerator.ExecutionAction.from(
                manifest: $0,
                generatorPaths: generatorPaths
            )
        }

        let postActions = try manifest.postActions.map {
            try XcodeProjectGenerator.ExecutionAction.from(
                manifest: $0,
                generatorPaths: generatorPaths
            )
        }

        let arguments = manifest.arguments.map { XcodeProjectGenerator.Arguments.from(manifest: $0) }

        var executableResolved: XcodeProjectGenerator.TargetReference?
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
