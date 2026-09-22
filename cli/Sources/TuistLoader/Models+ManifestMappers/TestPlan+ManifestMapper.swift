import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistAlert
import TuistConstants
import TuistSupport
import XcodeGraph

extension XcodeGraph.TestPlan {
    /// Maps a list of `ProjectDescription.TestPlan` manifests into graph-level `TestPlan` values,
    /// expanding globs for path entries and computing derived paths for generated ones. The first
    /// resolved plan is marked as the default.
    static func from(
        manifests: [ProjectDescription.TestPlan],
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
        for manifest in manifests {
            switch manifest {
            case let .path(path):
                try await appendPathEntry(
                    path: path,
                    generatorPaths: generatorPaths,
                    schemeName: schemeName,
                    fileSystem: fileSystem,
                    into: &resolved
                )
            case let .generated(name, testTargets, path, defaultOptions, options):
                let resolvedPath: AbsolutePath = if let explicitPath = path {
                    try generatorPaths.resolve(path: explicitPath)
                } else {
                    derivedDirectory.appending(component: "\(name).xctestplan")
                }
                let targets = try testTargets.map {
                    try TestableTarget.from(manifest: $0, generatorPaths: generatorPaths)
                }
                resolved.append(
                    XcodeGraph.TestPlan(
                        path: resolvedPath,
                        testTargets: targets,
                        isDefault: resolved.isEmpty,
                        kind: .generated(
                            defaultOptions: try mappedOptions(
                                defaultOptions,
                                generatorPaths: generatorPaths
                            ),
                            options: try options.mapValues {
                                try mappedOptions($0, generatorPaths: generatorPaths)
                            }
                        )
                    )
                )
            }
        }

        return resolved
    }

    private static func mappedOptions(
        _ options: ProjectDescription.TestPlanOptions,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeGraph.TestPlanOptions {
        return try XcodeGraph.TestPlanOptions(
            arguments: options.arguments.map { Arguments.from(manifest: $0) },
            codeCoverage: try options.codeCoverage.map { codeCoverage in
                switch codeCoverage {
                case .disabled:
                    .disabled
                case .allTargets:
                    .allTargets
                case let .specificTargets(targets):
                    .specificTargets(try targets.map { target in
                        try TargetReference(
                            projectPath: try generatorPaths.resolveSchemeActionProjectPath(target.projectPath),
                            name: target.targetName
                        )
                    })
                }
            },
            expandVariableFromTarget: try options.expandVariableFromTarget.map { try TargetReference(
                projectPath: generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                name: $0.targetName
            ) },
            language: options.language?.identifier,
            region: options.region,
            preferredScreenCaptureFormat: options.preferredScreenCaptureFormat.map { .from(manifest: $0) },
            testExecutionOrdering: options.testExecutionOrdering?.rawValue,
            parallelizationMode: options.parallelizationMode?.rawValue,
            testRepetitionMode: options.testRepetitionMode?.rawValue,
            maximumTestRepetitions: options.maximumTestRepetitions,
            repeatInNewRunnerProcess: options.repeatInNewRunnerProcess,
            testTimeoutsEnabled: options.testTimeoutsEnabled,
            defaultTestExecutionTimeAllowance: options.defaultTestExecutionTimeAllowance,
            maximumTestExecutionTimeAllowance: options.maximumTestExecutionTimeAllowance,
            userAttachmentLifetime: options.userAttachmentLifetime?.rawValue,
            uiTestingScreenshotsLifetime: options.uiTestingScreenshotsLifetime?.rawValue,
            areLocalizationScreenshotsEnabled: options.areLocalizationScreenshotsEnabled,
            diagnosticCollectionPolicy: options.diagnosticCollectionPolicy?.rawValue,
            distributor: options.distributor?.rawValue,
            locationScenarioIdentifier: options.locationScenario?.identifier,
            locationScenarioReferenceType: options.locationScenario?.referenceType.rawValue,
            testInteropMode: options.testInteropMode?.rawValue,
            applicationCrashDetectionSeverity: options.applicationCrashDetectionSeverity?.rawValue,
            addressSanitizer: options.addressSanitizer.map { addressSanitizer in
                switch addressSanitizer {
                case .disabled:
                    .disabled
                case let .enabled(detectStackUseAfterReturn):
                    .enabled(detectStackUseAfterReturn: detectStackUseAfterReturn)
                }
            },
            threadSanitizerEnabled: options.threadSanitizerEnabled,
            mainThreadCheckerEnabled: options.mainThreadCheckerEnabled,
            performanceAntipatternCheckerEnabled: options.performanceAntipatternCheckerEnabled,
            undefinedBehaviorSanitizerEnabled: options.undefinedBehaviorSanitizerEnabled,
            zombieObjectsEnabled: options.zombieObjectsEnabled,
            guardMallocEnabled: options.guardMallocEnabled,
            mallocScribbleEnabled: options.mallocScribbleEnabled,
            mallocGuardEdgesEnabled: options.mallocGuardEdgesEnabled,
            mallocStackLogging: options.mallocStackLogging?.rawValue,
            checkedAllocations: options.checkedAllocations.map { checkedAllocations in
                switch checkedAllocations {
                case .disabled:
                    .disabled
                case .always:
                    .always
                case .mteOnly:
                    .mteOnly
                }
            },
            runtimeIssueDetection: options.runtimeIssueDetection.map(runtimeIssueDetectionPolicy),
            mainThreadCheckerDetectionPolicy: options.mainThreadCheckerDetectionPolicy.map(runtimeIssueDetectionPolicy),
            threadPerformanceCheckerRuntimeIssueDetection: options.threadPerformanceCheckerRuntimeIssueDetection.map(
                runtimeIssueDetectionPolicy
            ),
            memoryTaggingAddressSanitizerEnabled: options.memoryTaggingAddressSanitizerEnabled
        )
    }

    private static func runtimeIssueDetectionPolicy(
        _ policy: ProjectDescription.TestPlanRuntimeIssueDetectionPolicy
    ) -> XcodeGraph.TestPlanRuntimeIssueDetectionPolicy {
        switch policy {
        case .disabled:
            .disabled
        case let .enabled(severity):
            .enabled(severity.rawValue)
        }
    }

    /// Reads an existing `.xctestplan` file and maps it into the graph model.
    /// `TestPlan.from(manifests:...)` is the normal entry point; this method is exposed for call
    /// sites that already have a resolved path in hand.
    static func from(
        path: AbsolutePath,
        isDefault: Bool,
        generatorPaths: GeneratorPaths
    ) async throws -> XcodeGraph.TestPlan {
        let fileSystem = FileSystem()
        let xcTestPlan: XCTestPlan = try await fileSystem.readJSONFile(at: path, decoder: JSONDecoder())

        return try XcodeGraph.TestPlan(
            path: path,
            testTargets: xcTestPlan.testTargets.map { testTarget in
                let relativeProjectPath = projectRelativePath(from: testTarget.target.containerPath)
                let projectPath: AbsolutePath = if relativeProjectPath.isEmpty {
                    generatorPaths.manifestDirectory
                } else {
                    try generatorPaths.resolve(path: .relativeToManifest(relativeProjectPath))
                        .removingLastComponent()
                }
                return try TestableTarget(
                    target: TargetReference(
                        projectPath: projectPath,
                        name: testTarget.target.name
                    ),
                    skipped: !(testTarget.enabled ?? true)
                )
            },
            isDefault: isDefault
        )
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
                    let testPlan = try await XcodeGraph.TestPlan.from(
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

        let testPlan = try await XcodeGraph.TestPlan.from(
            path: resolvedPath,
            isDefault: resolved.isEmpty,
            generatorPaths: generatorPaths
        )
        resolved.append(testPlan)
    }

    /// Strips the `container:` prefix from an `.xctestplan` container path, returning the
    /// project-relative portion that follows it. Returns the input unchanged when no prefix is
    /// present.
    private static func projectRelativePath(from containerPath: String) -> String {
        let prefix = "container:"
        guard containerPath.hasPrefix(prefix) else { return containerPath }
        return String(containerPath.dropFirst(prefix.count))
    }
}
