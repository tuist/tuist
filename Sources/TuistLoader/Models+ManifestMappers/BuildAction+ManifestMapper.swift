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

        let targets: [XcodeGraph.BuildAction.Target] = try manifest.targets.map {
            XcodeGraph.BuildAction.Target(TargetReference(
                projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.reference.projectPath),
                name: $0.reference.targetName
            ), buildFor: $0.buildFor?.map({ XcodeGraph.BuildAction.Target.BuildFor(fromBuildFor: $0) }))
        }
        return XcodeGraph.BuildAction(
            targets: targets,
            preActions: preActions,
            postActions: postActions,
            runPostActionsOnFailure: manifest.runPostActionsOnFailure
        )
    }
}

extension XcodeGraph.BuildAction.Target.BuildFor {
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
