import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.TestAction {
    static func from(manifest: ProjectDescription.TestAction,
                     projectPath _: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.TestAction {
        let targets = try manifest.targets.map { try TuistCore.TestableTarget.from(manifest: $0,
                                                                                   generatorPaths: generatorPaths) }
        let arguments = manifest.arguments.map { TuistCore.Arguments.from(manifest: $0) }
        let configurationName = manifest.configurationName
        let coverage = manifest.coverage
        let codeCoverageTargets = try manifest.codeCoverageTargets.map {
            TuistCore.TargetReference(projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                                      name: $0.targetName)
        }
        let preActions = try manifest.preActions.map { try TuistCore.ExecutionAction.from(manifest: $0,
                                                                                          generatorPaths: generatorPaths) }
        let postActions = try manifest.postActions.map { try TuistCore.ExecutionAction.from(manifest: $0,
                                                                                            generatorPaths: generatorPaths) }

        return TestAction(targets: targets,
                          arguments: arguments,
                          configurationName: configurationName,
                          coverage: coverage,
                          codeCoverageTargets: codeCoverageTargets,
                          preActions: preActions,
                          postActions: postActions)
    }
}
