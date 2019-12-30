import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.BuildAction: ModelConvertible {
    init(manifest: ProjectDescription.BuildAction, generatorPaths: GeneratorPaths) throws {
        let preActions = try manifest.preActions.map { try TuistCore.ExecutionAction(manifest: $0, generatorPaths: generatorPaths) }
        let postActions = try manifest.postActions.map { try TuistCore.ExecutionAction(manifest: $0, generatorPaths: generatorPaths) }
        let targets: [TuistCore.TargetReference] = try manifest.targets.map {
            .project(path: try generatorPaths.resolve(projectPath: $0.projectPath), target: $0.targetName)
        }
        self.init(targets: targets, preActions: preActions, postActions: postActions)
    }
}
