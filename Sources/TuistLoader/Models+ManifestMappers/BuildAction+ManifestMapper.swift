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
        let targets: [TuistGraph.BuildAction.Target] = try manifest.targets.map {
            .init(
                targetReference: TargetReference(
                    projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.targetReference.projectPath),
                    name: $0.targetReference.targetName
                ),
                buildFor: $0.buildFor.map({ .init(fromBuildFor: $0) })
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

extension TuistGraph.BuildAction.Target.BuildFor {
    init(fromBuildFor buildFor: ProjectDescription.BuildAction.Target.BuildFor) {
        switch buildFor {
        case .running: 
            self = .running
        case .testing: 
            self = .testing
        case .profiling: 
            self = .profiling
        case .archiving: 
            self = .archiving
        case .analyzing: 
            self = .analyzing
        }
    }
}
