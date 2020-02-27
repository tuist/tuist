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
        let targets = try manifest.targets.map { try TuistCore.TestableTarget.from(manifest: $0, generatorPaths: generatorPaths) }
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
        let diagnosticsOptions = Set(manifest.diagnosticsOptions.map { TuistCore.SchemeDiagnosticsOption.from(manifest: $0) })

        let language: String? = manifest.language
        let region: String? = manifest.region
        
        return TestAction(targets: targets,
                          arguments: arguments,
                          configurationName: configurationName,
                          coverage: coverage,
                          codeCoverageTargets: codeCoverageTargets,
                          preActions: preActions,
                          postActions: postActions,
                          diagnosticsOptions: diagnosticsOptions,
                          language: language,
                          region: region)
    }
}
