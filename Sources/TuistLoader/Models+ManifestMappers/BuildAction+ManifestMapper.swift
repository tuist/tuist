import Foundation
import Path
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.BuildAction {
    /// Maps a ProjectDescription.BuildAction instance into a XcodeGraph.BuildAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of build action model.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.BuildAction,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeGraph.BuildAction {
        let preActions = try manifest.preActions.map { try XcodeGraph.ExecutionAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let postActions = try manifest.postActions.map { try XcodeGraph.ExecutionAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
<<<<<<< HEAD
        let targets: [XcodeGraph.TargetReference] = try manifest.targets.map {
=======
        let targets: [TuistGraph.BuildAction.Target] = try manifest.targets.map {
>>>>>>> d9a6ea38d (Add BuildFor argument in BuildAction in generation scheme)
            .init(
                targetReference: TargetReference(
                    projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.targetReference.projectPath),
                    name: $0.targetReference.targetName
                ),
                buildFor: $0.buildFor.map({ .init(fromBuildFor: $0) })
            )
        }
        return XcodeGraph.BuildAction(
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
