import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistAlert
import TuistConstants
import TuistCore
import TuistSupport
import XcodeGraph

extension XcodeGraph.TestAction {
    // swiftlint:disable function_body_length
    // Maps a ProjectDescription.TestAction instance into a XcodeGraph.TestAction instance.
    // - Parameters:
    //   - manifest: Manifest representation of test action model.
    //   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.TestAction,
        generatorPaths: GeneratorPaths,
        schemeName: String? = nil
    ) async throws -> XcodeGraph
        .TestAction
    {
        // swiftlint:enable function_body_length
        let testPlans: [XcodeGraph.TestPlan]?
        let targets: [XcodeGraph.TestableTarget]
        let arguments: XcodeGraph.Arguments?
        let coverage: Bool
        let codeCoverageTargets: [XcodeGraph.TargetReference]
        let expandVariablesFromTarget: XcodeGraph.TargetReference?
        let diagnosticsOptions: XcodeGraph.SchemeDiagnosticsOptions
        let language: SchemeLanguage?
        let region: String?
        let preferredScreenCaptureFormat: XcodeGraph.ScreenCaptureFormat?
        let skippedTests: [String]?
        let fileSystem = FileSystem()

        if let generatedPlans = manifest.generatedTestPlans, !generatedPlans.isEmpty {
            let hasExplicitDefault = generatedPlans.contains(where: \.isDefault)
            let derivedDirectory = generatorPaths.manifestDirectory
                .appending(
                    components: Constants.DerivedDirectory.name,
                    Constants.DerivedDirectory.testPlans
                )
            var resolvedTestPlans: [XcodeGraph.TestPlan] = []

            for (index, plan) in generatedPlans.enumerated() {
                let resolvedPath = derivedDirectory.appending(component: "\(plan.name).xctestplan")
                let testTargets = try plan.testTargets.map {
                    try XcodeGraph.TestableTarget.from(manifest: $0, generatorPaths: generatorPaths)
                }
                let isDefault = hasExplicitDefault ? plan.isDefault : index == 0
                resolvedTestPlans.append(
                    XcodeGraph.TestPlan(
                        path: resolvedPath,
                        testTargets: testTargets,
                        isDefault: isDefault,
                        isGenerated: true
                    )
                )
            }

            testPlans = resolvedTestPlans

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
        } else if let plans = manifest.testPlans {
            var resolvedTestPlans: [XcodeGraph.TestPlan] = []

            for path in plans {
                let resolvedPath = try generatorPaths.resolve(path: path)
                let pathString = resolvedPath.pathString

                // Check if path contains glob patterns
                if pathString.contains("*") {
                    let globPathString = String(pathString.dropFirst())

                    do {
                        let globPaths = try await fileSystem
                            .throwingGlob(directory: .root, include: [globPathString])
                            .collect()
                            .filter { $0.extension == "xctestplan" }
                            .sorted()

                        for globPath in globPaths {
                            let testPlan = try await TestPlan.from(
                                path: globPath,
                                isDefault: resolvedTestPlans.isEmpty,
                                generatorPaths: generatorPaths
                            )
                            resolvedTestPlans.append(testPlan)
                        }
                    } catch GlobError.nonExistentDirectory {
                        // Skip non-existent glob patterns
                        continue
                    }
                } else {
                    // Handle as literal path
                    if try await fileSystem.exists(resolvedPath) {
                        if resolvedPath.extension == "xctestplan" {
                            let testPlan = try await TestPlan.from(
                                path: resolvedPath,
                                isDefault: resolvedTestPlans.isEmpty,
                                generatorPaths: generatorPaths
                            )
                            resolvedTestPlans.append(testPlan)
                        }
                    } else {
                        let schemeContext = schemeName.map { " referenced by the scheme '\($0)'" } ?? ""
                        AlertController.current.warning(
                            .alert(
                                "Test plan \(resolvedPath.basename) does not exist at \(resolvedPath.pathString)\(schemeContext)"
                            )
                        )
                    }
                }
            }

            testPlans = resolvedTestPlans.isEmpty ? nil : resolvedTestPlans

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
                .map { try XcodeGraph.TestableTarget.from(manifest: $0, generatorPaths: generatorPaths) }
            arguments = manifest.arguments.map { XcodeGraph.Arguments.from(manifest: $0) }
            coverage = manifest.options.coverage
            codeCoverageTargets = try manifest.options.codeCoverageTargets.map {
                XcodeGraph.TargetReference(
                    projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                    name: $0.targetName
                )
            }
            expandVariablesFromTarget = try manifest.expandVariableFromTarget.map {
                XcodeGraph.TargetReference(
                    projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                    name: $0.targetName
                )
            }
            diagnosticsOptions = XcodeGraph.SchemeDiagnosticsOptions.from(manifest: manifest.diagnosticsOptions)
            language = manifest.options.language
            region = manifest.options.region
            preferredScreenCaptureFormat = manifest.options.preferredScreenCaptureFormat
                .map { .from(manifest: $0) }

            // not used when using targets
            testPlans = nil
            skippedTests = manifest.skippedTests
        }

        let configurationName = manifest.configuration.rawValue
        let preActions = try manifest.preActions.map { try XcodeGraph.ExecutionAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let postActions = try manifest.postActions.map { try XcodeGraph.ExecutionAction.from(
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
