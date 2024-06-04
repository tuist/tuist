import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import XcodeProjectGenerator
import TuistSupport

extension XcodeProjectGenerator.TestAction {
    // swiftlint:disable function_body_length
    /// Maps a ProjectDescription.TestAction instance into a XcodeProjectGenerator.TestAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of test action model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.TestAction, generatorPaths: GeneratorPaths) throws -> XcodeProjectGenerator.TestAction {
        // swiftlint:enable function_body_length
        let testPlans: [XcodeProjectGenerator.TestPlan]?
        let targets: [XcodeProjectGenerator.TestableTarget]
        let arguments: XcodeProjectGenerator.Arguments?
        let coverage: Bool
        let codeCoverageTargets: [XcodeProjectGenerator.TargetReference]
        let expandVariablesFromTarget: XcodeProjectGenerator.TargetReference?
        let diagnosticsOptions: XcodeProjectGenerator.SchemeDiagnosticsOptions
        let language: SchemeLanguage?
        let region: String?
        let preferredScreenCaptureFormat: XcodeProjectGenerator.ScreenCaptureFormat?
        let skippedTests: [String]?

        if let plans = manifest.testPlans {
            testPlans = try plans.enumerated().compactMap { index, path in
                let resolvedPath = try generatorPaths.resolve(path: path)
                guard FileHandler.shared.exists(resolvedPath) else { return nil }
                return try TestPlan(path: resolvedPath, isDefault: index == 0, generatorPaths: generatorPaths)
            }

            // not used when using test plans
            targets = []
            arguments = nil
            coverage = false
            codeCoverageTargets = []
            expandVariablesFromTarget = nil
            diagnosticsOptions = .init()
            language = nil
            region = nil
            preferredScreenCaptureFormat = nil
            skippedTests = nil
        } else {
            targets = try manifest.targets
                .map { try XcodeProjectGenerator.TestableTarget.from(manifest: $0, generatorPaths: generatorPaths) }
            arguments = manifest.arguments.map { XcodeProjectGenerator.Arguments.from(manifest: $0) }
            coverage = manifest.options.coverage
            codeCoverageTargets = try manifest.options.codeCoverageTargets.map {
                XcodeProjectGenerator.TargetReference(
                    projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                    name: $0.targetName
                )
            }
            expandVariablesFromTarget = try manifest.expandVariableFromTarget.map {
                XcodeProjectGenerator.TargetReference(
                    projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                    name: $0.targetName
                )
            }
            diagnosticsOptions = XcodeProjectGenerator.SchemeDiagnosticsOptions.from(manifest: manifest.diagnosticsOptions)
            language = manifest.options.language
            region = manifest.options.region
            preferredScreenCaptureFormat = manifest.options.preferredScreenCaptureFormat
                .map { .from(manifest: $0) }

            // not used when using targets
            testPlans = nil
            skippedTests = manifest.skippedTests
        }

        let configurationName = manifest.configuration.rawValue
        let preActions = try manifest.preActions.map { try XcodeProjectGenerator.ExecutionAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let postActions = try manifest.postActions.map { try XcodeProjectGenerator.ExecutionAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }

        return TestAction(
            targets: targets,
            arguments: arguments,
            configurationName: configurationName,
            attachDebugger: manifest.attachDebugger,
            coverage: coverage,
            codeCoverageTargets: codeCoverageTargets,
            expandVariableFromTarget: expandVariablesFromTarget,
            preActions: preActions,
            postActions: postActions,
            diagnosticsOptions: diagnosticsOptions,
            language: language?.identifier,
            region: region,
            preferredScreenCaptureFormat: preferredScreenCaptureFormat,
            testPlans: testPlans,
            skippedTests: skippedTests
        )
    }
}
