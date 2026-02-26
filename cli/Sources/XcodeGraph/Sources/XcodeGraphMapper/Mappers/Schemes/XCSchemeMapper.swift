import FileSystem
import Foundation
import Path
import XcodeGraph
import XcodeProj

/// A protocol defining how to map a single `XCScheme` object (and its actions) into a domain `Scheme` model.
///
/// Conforming types translate a raw `XCScheme` instance, including its build, test, run, archive, profile,
/// and analyze actions, into a `Scheme` model ready for analysis, code generation, or tooling integration.
protocol SchemeMapping {
    /// Maps a single `XCScheme` into a `Scheme` model.
    ///
    /// - Parameters:
    ///   - xcscheme: The `XCScheme` to map.
    ///   - shared: Indicates whether the scheme is shared.
    ///   - graphType: Specifies if we’re dealing with a workspace or project for path resolution.
    /// - Returns: A `Scheme` model corresponding to the given `XCScheme`.
    /// - Throws: If any of the scheme's actions (build, test, run, etc.) cannot be resolved.
    func map(
        _ xcscheme: XCScheme,
        shared: Bool,
        graphType: XcodeMapperGraphType
    ) async throws -> Scheme
}

/// A mapper responsible for converting an `XCScheme` object into a `Scheme` model.
///
/// `XCSchemeMapper` resolves references to targets, environment variables, and all scheme actions.
/// The resulting `Scheme` models enable analysis, code generation, or integration with custom tooling.
struct XCSchemeMapper: SchemeMapping {
    private let fileSystem: FileSysteming
    private let jsonDecoder = JSONDecoder()

    init(
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.fileSystem = fileSystem
    }

    // MARK: - Public API

    func map(
        _ xcscheme: XCScheme,
        shared: Bool,
        graphType: XcodeMapperGraphType
    ) async throws -> Scheme {
        Scheme(
            name: xcscheme.name,
            shared: shared,
            hidden: false,
            buildAction: try mapBuildAction(action: xcscheme.buildAction, graphType: graphType),
            testAction: try await mapTestAction(action: xcscheme.testAction, graphType: graphType),
            runAction: try mapRunAction(action: xcscheme.launchAction, graphType: graphType),
            archiveAction: try mapArchiveAction(action: xcscheme.archiveAction),
            profileAction: try mapProfileAction(action: xcscheme.profileAction, graphType: graphType),
            analyzeAction: try mapAnalyzeAction(action: xcscheme.analyzeAction)
        )
    }

    // MARK: - Action Mappings

    /// Maps the optional build action into a domain `BuildAction`, or returns `nil` if not present.
    private func mapBuildAction(
        action: XCScheme.BuildAction?,
        graphType: XcodeMapperGraphType
    ) throws -> BuildAction? {
        guard let action else { return nil }

        let targets = try action.buildActionEntries.compactMap {
            try mapTargetReference(buildableReference: $0.buildableReference, graphType: graphType)
        }

        return BuildAction(
            targets: targets,
            preActions: [],
            postActions: [],
            parallelizeBuild: action.parallelizeBuild,
            runPostActionsOnFailure: action.runPostActionsOnFailure ?? false,
            findImplicitDependencies: action.buildImplicitDependencies
        )
    }

    /// Maps the optional test action into a domain `TestAction`, or returns `nil` if not present.
    private func mapTestAction(
        action: XCScheme.TestAction?,
        graphType: XcodeMapperGraphType
    ) async throws -> TestAction? {
        guard let action else { return nil }

        let testTargets = try action.testables.compactMap { testable in
            let targetRef = try mapTargetReference(
                buildableReference: testable.buildableReference,
                graphType: graphType
            )
            return TestableTarget(target: targetRef, skipped: testable.skipped)
        }

        let arguments = mapArguments(
            environmentVariables: action.environmentVariables,
            commandlineArguments: action.commandlineArguments
        )
        let diagnosticsOptions = SchemeDiagnosticsOptions(action: action)

        var testPlans: [TestPlan]?
        if let actionTestPlans = action.testPlans {
            testPlans = []
            for testPlan in actionTestPlans {
                testPlans?.append(
                    try await mapTestPlan(testPlan, graphType: graphType)
                )
            }
        }

        return TestAction(
            targets: testTargets,
            arguments: arguments,
            configurationName: action.buildConfiguration,
            attachDebugger: true,
            coverage: action.codeCoverageEnabled,
            codeCoverageTargets: [],
            expandVariableFromTarget: nil,
            preActions: [],
            postActions: [],
            diagnosticsOptions: diagnosticsOptions,
            language: action.language,
            region: action.region,
            testPlans: testPlans
        )
    }

    private func mapTestPlan(
        _ testPlan: XCScheme.TestPlanReference,
        graphType: XcodeMapperGraphType
    ) async throws -> TestPlan {
        let testPlanPath = try containerPath(from: testPlan.reference, graphType: graphType)
        let xctestPlan: XCTestPlan = try await fileSystem.readJSONFile(at: testPlanPath)

        return TestPlan(
            path: testPlanPath,
            testTargets: try xctestPlan.testTargets.map {
                let parallelization: TestableTarget.Parallelization = switch $0.parallelizable {
                case .none:
                    .swiftTestingOnly
                case .some(true):
                    .all
                case .some(false):
                    .none
                }
                let containerPath = try containerPath(
                    from: $0.target.containerPath,
                    graphType: graphType
                )
                let projectPath: AbsolutePath
                if containerPath.extension == nil {
                    projectPath = containerPath
                } else {
                    projectPath = containerPath.parentDirectory
                }

                return TestableTarget(
                    target: TargetReference(
                        projectPath: projectPath,
                        name: $0.target.name
                    ),
                    parallelization: parallelization
                )
            },
            isDefault: testPlan.default
        )
    }

    private func containerPath(
        from containerReference: String,
        graphType: XcodeMapperGraphType
    ) throws -> AbsolutePath {
        let relativeContainerPath = try RelativePath(validating: containerReference.replacingOccurrences(
            of: "container:",
            with: ""
        ))
        switch graphType {
        case let .workspace(xcworkspace):
            return xcworkspace.workspacePath.parentDirectory.appending(relativeContainerPath)
        case let .project(xcodeProj):
            return xcodeProj.projectPath.parentDirectory.appending(relativeContainerPath)
        }
    }

    /// Maps the optional run (launch) action into a domain `RunAction`, or returns `nil` if not present.
    private func mapRunAction(
        action: XCScheme.LaunchAction?,
        graphType: XcodeMapperGraphType
    ) throws -> RunAction? {
        guard let action else { return nil }

        let executable: TargetReference? = try {
            if let buildableRef = action.runnable?.buildableReference {
                return try mapTargetReference(buildableReference: buildableRef, graphType: graphType)
            }
            return nil
        }()

        let arguments = mapArguments(
            environmentVariables: action.environmentVariables,
            commandlineArguments: action.commandlineArguments
        )
        let diagnosticsOptions = SchemeDiagnosticsOptions(action: action)
        // If no debugger is explicitly chosen, Xcode uses the default lldb (true).
        let attachDebugger = action.selectedDebuggerIdentifier.isEmpty

        return RunAction(
            configurationName: action.buildConfiguration,
            attachDebugger: attachDebugger,
            customLLDBInitFile: nil,
            preActions: [],
            postActions: [],
            executable: executable,
            filePath: nil,
            arguments: arguments,
            options: RunActionOptions(),
            diagnosticsOptions: diagnosticsOptions,
            appClipInvocationURL: action.appClipInvocationURLString.flatMap { URL(string: $0) }
        )
    }

    /// Maps the optional archive action into a domain `ArchiveAction`, or returns `nil` if not present.
    private func mapArchiveAction(
        action: XCScheme.ArchiveAction?
    ) throws -> ArchiveAction? {
        guard let action else { return nil }
        return ArchiveAction(
            configurationName: action.buildConfiguration,
            revealArchiveInOrganizer: action.revealArchiveInOrganizer
        )
    }

    /// Maps the optional profile action into a domain `ProfileAction`, or returns `nil` if not present.
    func mapProfileAction(
        action: XCScheme.ProfileAction?,
        graphType: XcodeMapperGraphType
    ) throws -> ProfileAction? {
        guard let action else { return nil }

        let executable: TargetReference? = try {
            if let buildableRef = action.buildableProductRunnable?.buildableReference {
                return try mapTargetReference(buildableReference: buildableRef, graphType: graphType)
            }
            return nil
        }()

        return ProfileAction(
            configurationName: action.buildConfiguration,
            executable: executable
        )
    }

    /// Maps the optional analyze action into a domain `AnalyzeAction`, or returns `nil` if not present.
    private func mapAnalyzeAction(
        action: XCScheme.AnalyzeAction?
    ) throws -> AnalyzeAction? {
        guard let action else { return nil }
        return AnalyzeAction(configurationName: action.buildConfiguration)
    }

    // MARK: - Helper Methods

    /// Converts a buildable reference within a scheme to a `TargetReference`.
    private func mapTargetReference(
        buildableReference: XCScheme.BuildableReference,
        graphType: XcodeMapperGraphType
    ) throws -> TargetReference {
        let targetName = buildableReference.blueprintName
        let container = buildableReference.referencedContainer

        let projectPath: AbsolutePath
        switch graphType {
        case let .workspace(xcworkspace):
            // Container is relative to the workspace’s parent directory
            let relativeContainerPath = container.replacingOccurrences(of: "container:", with: "")
            let relPath = try RelativePath(validating: relativeContainerPath)
            projectPath = xcworkspace.workspacePath.parentDirectory.appending(relPath)
        case let .project(xcodeProj):
            projectPath = xcodeProj.projectPath.parentDirectory
        }

        return TargetReference(projectPath: projectPath, name: targetName)
    }

    /// Converts environment variables and command-line arguments into a unified `Arguments` model.
    private func mapArguments(
        environmentVariables: [XCScheme.EnvironmentVariable]?,
        commandlineArguments: XCScheme.CommandLineArguments?
    ) -> Arguments {
        let envVars = environmentVariables?.reduce(into: [String: EnvironmentVariable]()) { dict, variable in
            dict[variable.variable] = EnvironmentVariable(value: variable.value, isEnabled: variable.enabled)
        } ?? [:]

        let launchArgs = commandlineArguments?.arguments.map {
            LaunchArgument(name: $0.name, isEnabled: $0.enabled)
        } ?? []

        return Arguments(environmentVariables: envVars, launchArguments: launchArgs)
    }
}
