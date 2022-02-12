import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.BuildAction {
    /// Maps a ProjectDescription.BuildAction instance into a TuistGraph.BuildAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of build action model.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.BuildAction,
        generatorPaths: GeneratorPaths
    ) throws -> TuistGraph.BuildAction {
        let preActions = try manifest.preActions.map { try TuistGraph.ExecutionAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let postActions = try manifest.postActions.map { try TuistGraph.ExecutionAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let targets: [TuistGraph.TargetReference] = try manifest.targets.map {
            .init(
                projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                name: $0.targetName
            )
        }
        return TuistGraph.BuildAction(
            targets: targets,
            preActions: preActions,
            postActions: postActions,
            runPostActionsOnFailure: manifest.runPostActionsOnFailure
        )
    }
}
