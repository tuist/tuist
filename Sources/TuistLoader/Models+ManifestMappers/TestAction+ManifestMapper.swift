import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

extension TuistCore.TestAction {
    /// Maps a ProjectDescription.TestAction instance into a TuistCore.TestAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of test action model.
    ///   - pathResolver: A path resolver.
    static func from(manifest: ProjectDescription.TestAction, generatorPaths: GeneratorPaths) throws -> TuistCore.TestAction {
        let testPlans: [TuistCore.TestPlan]?
        let targets: [TuistCore.TestableTarget]
        let arguments: TuistCore.Arguments?
        let coverage: Bool
        let codeCoverageTargets: [TuistCore.TargetReference]
        let diagnosticsOptions: Set<TuistCore.SchemeDiagnosticsOption>
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
            diagnosticsOptions = Set()
            language = nil
            region = nil
        } else {
            targets = try manifest.targets.map { try TuistCore.TestableTarget.from(manifest: $0, generatorPaths: generatorPaths) }
            arguments = manifest.arguments.map { TuistCore.Arguments.from(manifest: $0) }
            coverage = manifest.coverage
            codeCoverageTargets = try manifest.codeCoverageTargets.map {
                TuistCore.TargetReference(projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                                          name: $0.targetName)
            }

            diagnosticsOptions = Set(manifest.diagnosticsOptions.map { TuistCore.SchemeDiagnosticsOption.from(manifest: $0) })
            language = manifest.language
            region = manifest.region

            // not used when using targets
            testPlans = nil
        }

        let configurationName = manifest.configurationName
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
                          postActions: postActions,
                          diagnosticsOptions: diagnosticsOptions,
                          language: language,
                          region: region,
                          testPlans: testPlans)
    }
}
