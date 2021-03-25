import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.TestAction {
    /// Maps a ProjectDescription.TestAction instance into a TuistGraph.TestAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of test action model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.TestAction, generatorPaths: GeneratorPaths) throws -> TuistGraph.TestAction {
        let testPlans: [TuistGraph.TestPlan]?
        let targets: [TuistGraph.TestableTarget]
        let arguments: TuistGraph.Arguments?
        let coverage: Bool
        let codeCoverageTargets: [TuistGraph.TargetReference]
        let expandVariablesFromTarget: TuistGraph.TargetReference?
        let diagnosticsOptions: Set<TuistGraph.SchemeDiagnosticsOption>
        let language: String?
        let region: String?

        if let plans = manifest.testPlans {
            testPlans = try plans.enumerated().map { index, path in
                try TestPlan(path: generatorPaths.resolve(path: path), isDefault: index == 0)
            }

            // not used when using test plans
            targets = []
            arguments = nil
            coverage = false
            codeCoverageTargets = []
            expandVariablesFromTarget = nil
            diagnosticsOptions = Set()
            language = nil
            region = nil
        } else {
            targets = try manifest.targets.map { try TuistGraph.TestableTarget.from(manifest: $0, generatorPaths: generatorPaths) }
            arguments = manifest.arguments.map { TuistGraph.Arguments.from(manifest: $0) }
            coverage = manifest.coverage
            codeCoverageTargets = try manifest.codeCoverageTargets.map {
                TuistGraph.TargetReference(
                    projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                    name: $0.targetName
                )
            }
            expandVariablesFromTarget = try manifest.expandVariableFromTarget.map {
                TuistGraph.TargetReference(
                    projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                    name: $0.targetName
                )
            }

            diagnosticsOptions = Set(manifest.diagnosticsOptions.map { TuistGraph.SchemeDiagnosticsOption.from(manifest: $0) })
            language = manifest.language
            region = manifest.region

            // not used when using targets
            testPlans = nil
        }

        let configurationName = manifest.configurationName
        let preActions = try manifest.preActions.map { try TuistGraph.ExecutionAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let postActions = try manifest.postActions.map { try TuistGraph.ExecutionAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }

        return TestAction(
            targets: targets,
            arguments: arguments,
            configurationName: configurationName,
            coverage: coverage,
            codeCoverageTargets: codeCoverageTargets,
            expandVariableFromTarget: expandVariablesFromTarget,
            preActions: preActions,
            postActions: postActions,
            diagnosticsOptions: diagnosticsOptions,
            language: language,
            region: region,
            testPlans: testPlans
        )
    }
}
