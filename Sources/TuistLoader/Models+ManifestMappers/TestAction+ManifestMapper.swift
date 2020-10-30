import Foundation
import ProjectDescription
import TSCBasic
import TuistCore

extension TuistCore.TestAction {
    /// Maps a ProjectDescription.TestAction instance into a TuistCore.TestAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of test action model.
    ///   - generatorPaths: Generator paths.
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
            let defaultPlan = try TuistCore.TestPlan.from(path: plans.default, isDefault: true, generatorPaths: generatorPaths)
            let otherPlans = try plans.other.map { try TuistCore.TestPlan.from(path: $0, isDefault: false, generatorPaths: generatorPaths) }

            testPlans = [defaultPlan] + otherPlans

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

extension TuistCore.TestPlan {
    static func from(path: Path, isDefault: Bool, generatorPaths: GeneratorPaths) throws -> Self {
        try Self(path: generatorPaths.resolve(path: path),
                 isDefault: isDefault)
    }
}
