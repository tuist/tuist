import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import XcodeProjectGenerator

extension XcodeProjectGenerator.BuildAction {
    /// Maps a ProjectDescription.BuildAction instance into a XcodeProjectGenerator.BuildAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of build action model.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.BuildAction,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeProjectGenerator.BuildAction {
        let preActions = try manifest.preActions.map { try XcodeProjectGenerator.ExecutionAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let postActions = try manifest.postActions.map { try XcodeProjectGenerator.ExecutionAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let targets: [XcodeProjectGenerator.TargetReference] = try manifest.targets.map {
            .init(
                projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                name: $0.targetName
            )
        }
        return XcodeProjectGenerator.BuildAction(
            targets: targets,
            preActions: preActions,
            postActions: postActions,
            runPostActionsOnFailure: manifest.runPostActionsOnFailure
        )
    }
}
