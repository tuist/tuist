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

        if let entries = manifest.testPlans, !entries.isEmpty {
            let resolvedTestPlans = try await XcodeGraph.TestPlan.resolve(
                entries: entries,
                generatorPaths: generatorPaths,
                schemeName: schemeName,
                fileSystem: fileSystem
            )

            testPlans = resolvedTestPlans.isEmpty ? nil : resolvedTestPlans

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

extension XcodeGraph.TestPlan {
    /// Resolves a list of `ProjectDescription.TestPlan` entries into the graph's `TestPlan` values,
    /// expanding globs for path entries and computing derived paths for generated ones. The first
    /// resolved plan is marked as the default.
    static func resolve(
        entries: [ProjectDescription.TestPlan],
        generatorPaths: GeneratorPaths,
        schemeName: String?,
        fileSystem: FileSystem
    ) async throws -> [XcodeGraph.TestPlan] {
        let derivedDirectory = generatorPaths.manifestDirectory
            .appending(
                components: Constants.DerivedDirectory.name,
                Constants.DerivedDirectory.testPlans
            )

        var resolved: [XcodeGraph.TestPlan] = []
        for entry in entries {
            switch entry.kind {
            case let .path(path):
                try await appendPathEntry(
                    path: path,
                    generatorPaths: generatorPaths,
                    schemeName: schemeName,
                    fileSystem: fileSystem,
                    into: &resolved
                )
            case let .generated(name, testTargets, path):
                let resolvedPath: AbsolutePath = if let explicitPath = path {
                    try generatorPaths.resolve(path: explicitPath)
                } else {
                    derivedDirectory.appending(component: "\(name).xctestplan")
                }
                let targets = try testTargets.map {
                    try XcodeGraph.TestableTarget.from(manifest: $0, generatorPaths: generatorPaths)
                }
                resolved.append(
                    XcodeGraph.TestPlan(
                        path: resolvedPath,
                        testTargets: targets,
                        isDefault: resolved.isEmpty,
                        isGenerated: true
                    )
                )
            }
        }

        return resolved
    }

    private static func appendPathEntry(
        path: ProjectDescription.Path,
        generatorPaths: GeneratorPaths,
        schemeName: String?,
        fileSystem: FileSystem,
        into resolved: inout [XcodeGraph.TestPlan]
    ) async throws {
        let resolvedPath = try generatorPaths.resolve(path: path)
        let pathString = resolvedPath.pathString

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
                        isDefault: resolved.isEmpty,
                        generatorPaths: generatorPaths
                    )
                    resolved.append(testPlan)
                }
            } catch GlobError.nonExistentDirectory {
                // Skip non-existent glob patterns.
            }
            return
        }

        guard try await fileSystem.exists(resolvedPath) else {
            let schemeContext = schemeName.map { " referenced by the scheme '\($0)'" } ?? ""
            AlertController.current.warning(
                .alert(
                    "Test plan \(resolvedPath.basename) does not exist at \(resolvedPath.pathString)\(schemeContext)"
                )
            )
            return
        }

        guard resolvedPath.extension == "xctestplan" else { return }

        let testPlan = try await TestPlan.from(
            path: resolvedPath,
            isDefault: resolved.isEmpty,
            generatorPaths: generatorPaths
        )
        resolved.append(testPlan)
    }
}
