import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.TestAction: ModelConvertible {
    init(manifest: ProjectDescription.TestAction, generatorPaths: GeneratorPaths) throws {
        let targets = try manifest.targets.map { try TuistCore.TestableTarget(manifest: $0, generatorPaths: generatorPaths) }
        let arguments = try manifest.arguments.map { try TuistCore.Arguments(manifest: $0, generatorPaths: generatorPaths) }
        let configurationName = manifest.configurationName
        let coverage = manifest.coverage
        let codeCoverageTargets = try manifest.codeCoverageTargets.map {
            TuistCore.TargetReference(projectPath: try generatorPaths.resolve(projectPath: $0.projectPath),
                                      name: $0.targetName)
        }
        let preActions = try manifest.preActions.map { try TuistCore.ExecutionAction(manifest: $0, generatorPaths: generatorPaths) }
        let postActions = try manifest.postActions.map { try TuistCore.ExecutionAction(manifest: $0, generatorPaths: generatorPaths) }

        self.init(targets: targets,
                  arguments: arguments,
                  configurationName: configurationName,
                  coverage: coverage,
                  codeCoverageTargets: codeCoverageTargets,
                  preActions: preActions,
                  postActions: postActions)
    }
}
