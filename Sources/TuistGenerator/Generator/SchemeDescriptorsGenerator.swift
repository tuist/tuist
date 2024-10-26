import Foundation
import Path
import TSCUtility
import TuistCore
import TuistSupport
import XcodeGraph
import XcodeProj

/// Protocol that defines the interface of the schemes generation.
protocol SchemeDescriptorsGenerating {
    /// Generates the schemes for the workspace targets.
    ///
    /// - Parameters:
    ///   - workspace: Workspace model.
    ///   - xcworkspacePath: Path to the workspace.
    ///   - generatedProjects: Generated Xcode projects.
    ///   - graphTraverser: Graph traverser.
    /// - Throws: A FatalError if the generation of the schemes fails.
    func generateWorkspaceSchemes(
        workspace: Workspace,
        generatedProjects: [AbsolutePath: GeneratedProject],
        graphTraverser: GraphTraversing
    ) throws -> [SchemeDescriptor]

    /// Generates the schemes for the project targets.
    ///
    /// - Parameters:
    ///   - project: Project manifest.
    ///   - xcprojectPath: Path to the Xcode project.
    ///   - generatedProject: Generated Xcode project.
    ///   - graphTraverser: Graph traverser.
    /// - Throws: A FatalError if the generation of the schemes fails.
    func generateProjectSchemes(
        project: Project,
        generatedProject: GeneratedProject,
        graphTraverser: GraphTraversing
    ) throws -> [SchemeDescriptor]
}

extension XCScheme {
    static let posixSpawnLauncher = "Xcode.IDEFoundation.Launcher.PosixSpawn"
}

// swiftlint:disable:next type_body_length
final class SchemeDescriptorsGenerator: SchemeDescriptorsGenerating {
    private enum Constants {
        /// Default last upgrade version for generated schemes.
        static let defaultLastUpgradeVersion = "1010"

        /// Default version for generated schemes.
        static let defaultVersion = "1.3"

        struct LaunchAction {
            var launcher: String
            var askForAppToLaunch: Bool?
            var launchAutomaticallySubstyle: String?

            static var `default`: LaunchAction {
                LaunchAction(
                    launcher: XCScheme.defaultLauncher,
                    askForAppToLaunch: nil,
                    launchAutomaticallySubstyle: nil
                )
            }

            static var `extension`: LaunchAction {
                LaunchAction(
                    launcher: XCScheme.posixSpawnLauncher,
                    askForAppToLaunch: true,
                    launchAutomaticallySubstyle: "2"
                )
            }
        }
    }

    func generateWorkspaceSchemes(
        workspace: Workspace,
        generatedProjects: [AbsolutePath: GeneratedProject],
        graphTraverser: GraphTraversing
    ) throws -> [SchemeDescriptor] {
        let schemes = try workspace.schemes.map { scheme in
            try generateScheme(
                scheme: scheme,
                path: workspace.xcWorkspacePath.parentDirectory,
                graphTraverser: graphTraverser,
                generatedProjects: generatedProjects,
                lastUpgradeCheck: workspace.generationOptions.lastXcodeUpgradeCheck
            )
        }

        return schemes
    }

    func generateProjectSchemes(
        project: Project,
        generatedProject: GeneratedProject,
        graphTraverser: GraphTraversing
    ) throws -> [SchemeDescriptor] {
        try project.schemes.map { scheme in
            try generateScheme(
                scheme: scheme,
                path: project.xcodeProjPath.parentDirectory,
                graphTraverser: graphTraverser,
                generatedProjects: [project.xcodeProjPath: generatedProject],
                lastUpgradeCheck: project.lastUpgradeCheck
            )
        }
    }

    // swiftlint:disable function_body_length
    /// Generate schemes for a project or workspace.
    ///
    /// - Parameters:
    ///     - scheme: Project scheme.
    ///     - xcPath: Path to workspace's .xcworkspace or project's .xcodeproj.
    ///     - path: Path to workspace or project folder.
    ///     - graphTraverser: Graph traverser.
    ///     - generatedProjects: Project paths mapped to generated projects.
    private func generateScheme(
        scheme: Scheme,
        path: AbsolutePath,
        graphTraverser: GraphTraversing,
        generatedProjects: [AbsolutePath: GeneratedProject],
        lastUpgradeCheck: XcodeGraph.Version?
    ) throws -> SchemeDescriptor {
        let generatedBuildAction = try schemeBuildAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: path,
            generatedProjects: generatedProjects
        )
        let generatedTestAction = try schemeTestAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: path,
            generatedProjects: generatedProjects
        )
        let generatedLaunchAction = try schemeLaunchAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: path,
            generatedProjects: generatedProjects
        )
        let generatedProfileAction = try schemeProfileAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: path,
            generatedProjects: generatedProjects
        )
        let generatedAnalyzeAction = try schemeAnalyzeAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: path,
            generatedProjects: generatedProjects
        )
        let generatedArchiveAction = try schemeArchiveAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: path,
            generatedProjects: generatedProjects
        )

        let wasCreatedForAppExtension = isSchemeForAppExtension(scheme: scheme, graphTraverser: graphTraverser)

        let lastUpgradeVersion = lastUpgradeCheck?.xcodeStringValue ?? Constants.defaultLastUpgradeVersion

        let xcscheme = XCScheme(
            name: scheme.name,
            lastUpgradeVersion: lastUpgradeVersion,
            version: Constants.defaultVersion,
            buildAction: generatedBuildAction,
            testAction: generatedTestAction,
            launchAction: generatedLaunchAction,
            profileAction: generatedProfileAction,
            analyzeAction: generatedAnalyzeAction,
            archiveAction: generatedArchiveAction,
            wasCreatedForAppExtension: wasCreatedForAppExtension
        )

        return SchemeDescriptor(xcScheme: xcscheme, shared: scheme.shared, hidden: scheme.hidden)
    } // swiftlint:enable function_body_length

    /// Generates the scheme build action.
    ///
    /// - Parameters:
    ///   - scheme: Scheme manifest.
    ///   - graphTraverser: Graph traverser.
    ///   - rootPath: Path to the project or workspace.
    ///   - generatedProjects: Project paths mapped to generated projects.
    /// - Returns: Scheme build action.
    func schemeBuildAction(
        scheme: Scheme,
        graphTraverser: GraphTraversing,
        rootPath: AbsolutePath,
        generatedProjects: [AbsolutePath: GeneratedProject]
    ) throws -> XCScheme.BuildAction? {
        guard let buildAction = scheme.buildAction else { return nil }

        let buildFor: [XCScheme.BuildAction.Entry.BuildFor] = [
            .analyzing, .archiving, .profiling, .running, .testing,
        ]

        var entries: [XCScheme.BuildAction.Entry] = []
        var preActions: [XCScheme.ExecutionAction] = []
        var postActions: [XCScheme.ExecutionAction] = []

        for buildActionTarget in buildAction.targets {
            guard let buildActionGraphTarget = graphTraverser.target(
                path: buildActionTarget.projectPath,
                name: buildActionTarget.name
            ),
                let buildableReference = try createBuildableReference(
                    graphTarget: buildActionGraphTarget,
                    graphTraverser: graphTraverser,
                    rootPath: rootPath,
                    generatedProjects: generatedProjects
                )
            else {
                continue
            }
            entries.append(XCScheme.BuildAction.Entry(buildableReference: buildableReference, buildFor: buildFor))
        }

        preActions = try buildAction.preActions.map {
            try schemeExecutionAction(
                action: $0,
                graphTraverser: graphTraverser,
                generatedProjects: generatedProjects,
                rootPath: rootPath
            )
        }

        postActions = try buildAction.postActions.map {
            try schemeExecutionAction(
                action: $0,
                graphTraverser: graphTraverser,
                generatedProjects: generatedProjects,
                rootPath: rootPath
            )
        }

        return XCScheme.BuildAction(
            buildActionEntries: entries,
            preActions: preActions,
            postActions: postActions,
            parallelizeBuild: true,
            buildImplicitDependencies: buildAction.findImplicitDependencies,
            runPostActionsOnFailure: buildAction.runPostActionsOnFailure ? true : nil
        )
    }

    // swiftlint:disable function_body_length
    /// Generates the scheme test action.
    ///
    /// - Parameters:
    ///   - scheme: Scheme manifest.
    ///   - graphTraverser: Graph traverser.
    ///   - rootPath: Root path to either project or workspace.
    ///   - generatedProjects: Project paths mapped to generated projects.
    /// - Returns: Scheme test action.
    func schemeTestAction(
        scheme: Scheme,
        graphTraverser: GraphTraversing,
        rootPath: AbsolutePath,
        generatedProjects: [AbsolutePath: GeneratedProject]
    ) throws -> XCScheme.TestAction? {
        // Use empty action if nil, otherwise Xcode will create it anyway
        let testAction = scheme.testAction ?? .empty(
            withConfigurationName: scheme.runAction?.configurationName ?? BuildConfiguration.debug.name
        )

        var testables: [XCScheme.TestableReference] = []
        var preActions: [XCScheme.ExecutionAction] = []
        var postActions: [XCScheme.ExecutionAction] = []

        let testPlans: [XCScheme.TestPlanReference]? = testAction.testPlans?.map {
            XCScheme.TestPlanReference(
                reference: "container:\($0.path.relative(to: rootPath))",
                default: $0.isDefault
            )
        }

        let skippedTests = testAction.skippedTests?.map { value in
            XCScheme.TestItem(identifier: value)
        } ?? []

        for testableTarget in testAction.targets {
            guard let testableGraphTarget = graphTraverser.target(
                path: testableTarget.target.projectPath,
                name: testableTarget.target.name
            ),
                let reference = try createBuildableReference(
                    graphTarget: testableGraphTarget,
                    graphTraverser: graphTraverser,
                    rootPath: rootPath,
                    generatedProjects: generatedProjects
                )
            else {
                continue
            }

            var locationScenarioReference: XCScheme.LocationScenarioReference?

            if let locationScenario = testableTarget.simulatedLocation {
                var identifier = locationScenario.identifier

                if case let .gpxFile(gpxPath) = locationScenario {
                    let fileRelativePath = gpxPath.relative(to: graphTraverser.workspace.xcWorkspacePath)
                    identifier = fileRelativePath.pathString
                }

                locationScenarioReference = .init(
                    identifier: identifier,
                    referenceType: locationScenario.referenceType
                )
            }

            let testable = XCScheme.TestableReference(
                skipped: testableTarget.isSkipped,
                parallelizable: testableTarget.isParallelizable,
                randomExecutionOrdering: testableTarget.isRandomExecutionOrdering,
                buildableReference: reference,
                locationScenarioReference: locationScenarioReference,
                skippedTests: skippedTests
            )
            testables.append(testable)
        }

        preActions = try testAction.preActions.map { try schemeExecutionAction(
            action: $0,
            graphTraverser: graphTraverser,
            generatedProjects: generatedProjects,
            rootPath: rootPath
        ) }
        postActions = try testAction.postActions.map { try schemeExecutionAction(
            action: $0,
            graphTraverser: graphTraverser,
            generatedProjects: generatedProjects,
            rootPath: rootPath
        ) }

        var args: XCScheme.CommandLineArguments?
        var environments: [XCScheme.EnvironmentVariable]?

        if let arguments = testAction.arguments {
            args = XCScheme.CommandLineArguments(arguments: getCommandlineArguments(arguments.launchArguments))
            environments = environmentVariables(arguments.environmentVariables)
        }

        let codeCoverageTargets = try testAction.codeCoverageTargets
            .compactMap { (target: TargetReference) -> XCScheme.BuildableReference? in
                guard let graphTarget = graphTraverser.target(path: target.projectPath, name: target.name) else { return nil }
                return try testCoverageTargetReferences(
                    graphTarget: graphTarget,
                    graphTraverser: graphTraverser,
                    generatedProjects: generatedProjects,
                    rootPath: rootPath
                )
            }

        var macroExpansion: XCScheme.BuildableReference?
        if let expandVariableFromTarget = testAction.expandVariableFromTarget {
            guard let graphTarget = graphTraverser.target(
                path: expandVariableFromTarget.projectPath,
                name: expandVariableFromTarget.name
            )
            else {
                return nil
            }
            macroExpansion = try testCoverageTargetReferences(
                graphTarget: graphTarget,
                graphTraverser: graphTraverser,
                generatedProjects: generatedProjects,
                rootPath: rootPath
            )
        }

        let onlyGenerateCoverageForSpecifiedTargets = codeCoverageTargets.count > 0 ? true : nil

        let enableAddressSanitizer = testAction.diagnosticsOptions.addressSanitizerEnabled
        var enableASanStackUseAfterReturn = false
        if enableAddressSanitizer {
            enableASanStackUseAfterReturn = testAction.diagnosticsOptions.detectStackUseAfterReturnEnabled
        }
        let enableThreadSanitizer = testAction.diagnosticsOptions.threadSanitizerEnabled
        let disableMainThreadChecker = !testAction.diagnosticsOptions.mainThreadCheckerEnabled
        let shouldUseLaunchSchemeArgsEnv: Bool = args == nil && environments == nil
        let language = testAction.language
        let region = testAction.region
        let preferredScreenCaptureFormat: XCScheme.TestAction.ScreenCaptureFormat? =
            testAction.preferredScreenCaptureFormat.flatMap { format in
                switch format {
                case .screenshots:
                    return .screenshots
                case .screenRecording:
                    return .screenRecording
                }
            }

        return XCScheme.TestAction(
            buildConfiguration: testAction.configurationName,
            macroExpansion: macroExpansion,
            testables: testables,
            testPlans: testPlans,
            preActions: preActions,
            postActions: postActions,
            selectedDebuggerIdentifier: testAction.attachDebugger ? XCScheme.defaultDebugger : "",
            selectedLauncherIdentifier: testAction.attachDebugger ? XCScheme.defaultLauncher : XCScheme.posixSpawnLauncher,
            shouldUseLaunchSchemeArgsEnv: shouldUseLaunchSchemeArgsEnv,
            codeCoverageEnabled: testAction.coverage,
            codeCoverageTargets: codeCoverageTargets,
            onlyGenerateCoverageForSpecifiedTargets: onlyGenerateCoverageForSpecifiedTargets,
            enableAddressSanitizer: enableAddressSanitizer,
            enableASanStackUseAfterReturn: enableASanStackUseAfterReturn,
            enableThreadSanitizer: enableThreadSanitizer,
            disableMainThreadChecker: disableMainThreadChecker,
            commandlineArguments: args,
            environmentVariables: environments,
            language: language,
            region: region,
            preferredScreenCaptureFormat: preferredScreenCaptureFormat
        )
    } // swiftlint:enable function_body_length

    // swiftlint:disable function_body_length
    /// Generates the scheme launch action.
    ///
    /// - Parameters:
    ///   - scheme: Scheme manifest.
    ///   - graphTraverser: Graph traverser.
    ///   - rootPath: Root path to either project or workspace.
    ///   - generatedProjects: Project paths mapped to generated projects.
    /// - Returns: Scheme launch action.
    func schemeLaunchAction(
        scheme: Scheme,
        graphTraverser: GraphTraversing,
        rootPath: AbsolutePath,
        generatedProjects: [AbsolutePath: GeneratedProject]
    ) throws -> XCScheme.LaunchAction? {
        let specifiedExecutableTarget = scheme.runAction?.executable
        let defaultTarget = defaultTargetReference(scheme: scheme)
        guard let target = specifiedExecutableTarget ?? defaultTarget else { return nil }

        var buildableProductRunnable: XCScheme.BuildableProductRunnable?
        var macroExpansion: XCScheme.BuildableReference?
        var pathRunnable: XCScheme.PathRunnable?
        var defaultBuildConfiguration = BuildConfiguration.debug.name

        if let filePath = scheme.runAction?.filePath {
            pathRunnable = XCScheme.PathRunnable(filePath: filePath.pathString)
        } else {
            guard let graphTarget = graphTraverser.target(path: target.projectPath, name: target.name) else { return nil }
            defaultBuildConfiguration = graphTarget.project.defaultDebugBuildConfigurationName
            guard let buildableReference = try createBuildableReference(
                graphTarget: graphTarget,
                graphTraverser: graphTraverser,
                rootPath: rootPath,
                generatedProjects: generatedProjects
            ) else { return nil }

            if graphTarget.target.product.runnable {
                buildableProductRunnable = XCScheme.BuildableProductRunnable(
                    buildableReference: buildableReference,
                    runnableDebuggingMode: "0"
                )
            } else {
                macroExpansion = buildableReference
            }
        }

        if let expandVariableFromTarget = scheme.runAction?.expandVariableFromTarget,
           let graphTarget = graphTraverser.target(
               path: expandVariableFromTarget.projectPath,
               name: expandVariableFromTarget.name
           ),
           let buildableReference = try createBuildableReference(
               graphTarget: graphTarget,
               graphTraverser: graphTraverser,
               rootPath: rootPath,
               generatedProjects: generatedProjects
           )
        {
            // Xcode assigns the runnable target to the expand variables target by default.
            // Assigning the runnable target to macro expansion can lead to an unstable .xcscheme.
            // Initially, macroExpansion is added, but when the edit scheme editor is opened and closed, macroExpansion gets
            // removed.
            if buildableProductRunnable?.buildableReference != buildableReference {
                macroExpansion = buildableReference
            }
        }

        let launchStyle: XCScheme.LaunchAction.Style = {
            guard let style = scheme.runAction?.launchStyle else { return .auto }
            switch style {
            case .automatically:
                return .auto
            case .waitForExecutableToBeLaunched:
                return .wait
            }
        }()

        var commandlineArguments: XCScheme.CommandLineArguments?
        var environments: [XCScheme.EnvironmentVariable]?
        var storeKitConfigurationFileReference: XCScheme.StoreKitConfigurationFileReference?
        var locationScenarioReference: XCScheme.LocationScenarioReference?

        if let arguments = scheme.runAction?.arguments {
            commandlineArguments = XCScheme.CommandLineArguments(arguments: getCommandlineArguments(arguments.launchArguments))
            environments = environmentVariables(arguments.environmentVariables)
        }

        let buildConfiguration = scheme.runAction?.configurationName ?? defaultBuildConfiguration
        let enableAddressSanitizer = scheme.runAction?.diagnosticsOptions.addressSanitizerEnabled ?? false
        var enableASanStackUseAfterReturn = false
        if enableAddressSanitizer == true {
            enableASanStackUseAfterReturn = scheme.runAction?.diagnosticsOptions.detectStackUseAfterReturnEnabled ?? false
        }
        let enableThreadSanitizer = scheme.runAction?.diagnosticsOptions.threadSanitizerEnabled ?? false
        let disableMainThreadChecker = scheme.runAction?.diagnosticsOptions.mainThreadCheckerEnabled == false
        let disablePerformanceAntipatternChecker = scheme.runAction?.diagnosticsOptions
            .performanceAntipatternCheckerEnabled == false

        let launchActionConstants: Constants.LaunchAction
        let launcherIdentifier: String
        let debuggerIdentifier: String
        let isSchemeForAppExtension = isSchemeForAppExtension(scheme: scheme, graphTraverser: graphTraverser)
        if isSchemeForAppExtension == true {
            launchActionConstants = .extension
            debuggerIdentifier = ""
            launcherIdentifier = launchActionConstants.launcher
        } else {
            launchActionConstants = .default
            if let runAction = scheme.runAction {
                debuggerIdentifier = runAction.attachDebugger ? XCScheme.defaultDebugger : ""
                launcherIdentifier = runAction.attachDebugger ? launchActionConstants.launcher : XCScheme.posixSpawnLauncher
            } else {
                debuggerIdentifier = XCScheme.defaultDebugger
                launcherIdentifier = launchActionConstants.launcher
            }
        }

        let graphTarget = graphTraverser.target(path: target.projectPath, name: target.name)

        let customLLDBInitFilePath: RelativePath?
        if let customLLDBInitFile = scheme.runAction?.customLLDBInitFile,
           let graphTarget
        {
            customLLDBInitFilePath = customLLDBInitFile.relative(to: graphTarget.project.path)
        } else {
            customLLDBInitFilePath = nil
        }

        if let storeKitFilePath = scheme.runAction?.options.storeKitConfigurationPath {
            // the identifier is the relative path between the storekit file, and the xcode project
            let fileRelativePath = storeKitFilePath.relative(to: graphTraverser.workspace.xcWorkspacePath)
            storeKitConfigurationFileReference = .init(identifier: fileRelativePath.pathString)
        }

        if let locationScenario = scheme.runAction?.options.simulatedLocation {
            var identifier = locationScenario.identifier

            if case let .gpxFile(gpxPath) = locationScenario {
                let fileRelativePath = gpxPath.relative(to: graphTraverser.workspace.xcWorkspacePath)
                identifier = fileRelativePath.pathString
            }

            locationScenarioReference = .init(
                identifier: identifier,
                referenceType: locationScenario.referenceType
            )
        }

        let enableGPUFrameCaptureMode: XCScheme.LaunchAction.GPUFrameCaptureMode
        if let captureMode = scheme.runAction?.options.enableGPUFrameCaptureMode {
            switch captureMode {
            case .autoEnabled:
                enableGPUFrameCaptureMode = .autoEnabled
            case .metal:
                enableGPUFrameCaptureMode = .metal
            case .openGL:
                enableGPUFrameCaptureMode = .openGL
            case .disabled:
                enableGPUFrameCaptureMode = .disabled
            }
        } else {
            enableGPUFrameCaptureMode = .autoEnabled
        }

        let preActions = try scheme.runAction?.preActions.map {
            try schemeExecutionAction(
                action: $0,
                graphTraverser: graphTraverser,
                generatedProjects: generatedProjects,
                rootPath: rootPath
            )
        } ?? []

        let postActions = try scheme.runAction?.postActions.map {
            try schemeExecutionAction(
                action: $0,
                graphTraverser: graphTraverser,
                generatedProjects: generatedProjects,
                rootPath: rootPath
            )
        } ?? []

        return XCScheme.LaunchAction(
            runnable: buildableProductRunnable,
            buildConfiguration: buildConfiguration,
            preActions: preActions,
            postActions: postActions,
            macroExpansion: macroExpansion,
            selectedDebuggerIdentifier: debuggerIdentifier,
            selectedLauncherIdentifier: launcherIdentifier,
            launchStyle: launchStyle,
            askForAppToLaunch: launchActionConstants.askForAppToLaunch,
            pathRunnable: pathRunnable,
            locationScenarioReference: locationScenarioReference,
            enableGPUFrameCaptureMode: enableGPUFrameCaptureMode,
            enableAddressSanitizer: enableAddressSanitizer,
            enableASanStackUseAfterReturn: enableASanStackUseAfterReturn,
            enableThreadSanitizer: enableThreadSanitizer,
            disableMainThreadChecker: disableMainThreadChecker,
            disablePerformanceAntipatternChecker: disablePerformanceAntipatternChecker,
            commandlineArguments: commandlineArguments,
            environmentVariables: environments,
            language: scheme.runAction?.options.language,
            region: scheme.runAction?.options.region,
            launchAutomaticallySubstyle: launchActionConstants.launchAutomaticallySubstyle,
            storeKitConfigurationFileReference: storeKitConfigurationFileReference,
            customLLDBInitFile: customLLDBInitFilePath.map { "$(SRCROOT)/\($0.pathString)" }
        )
    } // swiftlint:enable function_body_length

    /// Generates the scheme profile action for a given target.
    ///
    /// - Parameters:
    ///   - scheme: Target manifest.
    ///   - graphTraverser: Graph traverser.
    ///   - rootPath: Root path to either project or workspace.
    ///   - generatedProjects: Project paths mapped to generated projects.
    /// - Returns: Scheme profile action.
    func schemeProfileAction( // swiftlint:disable:this function_body_length
        scheme: Scheme,
        graphTraverser: GraphTraversing,
        rootPath: AbsolutePath,
        generatedProjects: [AbsolutePath: GeneratedProject]
    ) throws -> XCScheme.ProfileAction? {
        guard var target = defaultTargetReference(scheme: scheme) else { return nil }
        var commandlineArguments: XCScheme.CommandLineArguments?
        var environments: [XCScheme.EnvironmentVariable]?

        if let action = scheme.profileAction, let executable = action.executable {
            target = executable
            if let arguments = action.arguments {
                commandlineArguments = XCScheme
                    .CommandLineArguments(arguments: getCommandlineArguments(arguments.launchArguments))
                environments = environmentVariables(arguments.environmentVariables)
            }
        } else if let action = scheme.runAction, let executable = action.executable {
            target = executable
            // arguments are inherited automatically from Launch Action (via `shouldUseLaunchSchemeArgsEnv`)
        }

        let shouldUseLaunchSchemeArgsEnv: Bool = commandlineArguments == nil && environments == nil

        guard let graphTarget = graphTraverser.target(path: target.projectPath, name: target.name) else { return nil }
        guard let buildableReference = try createBuildableReference(
            graphTarget: graphTarget,
            graphTraverser: graphTraverser,
            rootPath: rootPath,
            generatedProjects: generatedProjects
        ) else { return nil }

        var buildableProductRunnable: XCScheme.BuildableProductRunnable?
        var macroExpansion: XCScheme.BuildableReference?

        if graphTarget.target.product.runnable {
            buildableProductRunnable = XCScheme.BuildableProductRunnable(
                buildableReference: buildableReference,
                runnableDebuggingMode: "0"
            )
        } else {
            macroExpansion = buildableReference
        }

        let buildConfiguration = scheme.profileAction?
            .configurationName ?? defaultReleaseBuildConfigurationName(in: graphTarget.project)

        let preActions = try scheme.profileAction?.preActions.map {
            try schemeExecutionAction(
                action: $0,
                graphTraverser: graphTraverser,
                generatedProjects: generatedProjects,
                rootPath: rootPath
            )
        } ?? []

        let postActions = try scheme.profileAction?.postActions.map {
            try schemeExecutionAction(
                action: $0,
                graphTraverser: graphTraverser,
                generatedProjects: generatedProjects,
                rootPath: rootPath
            )
        } ?? []

        return XCScheme.ProfileAction(
            buildableProductRunnable: buildableProductRunnable,
            buildConfiguration: buildConfiguration,
            preActions: preActions,
            postActions: postActions,
            macroExpansion: macroExpansion,
            shouldUseLaunchSchemeArgsEnv: shouldUseLaunchSchemeArgsEnv,
            commandlineArguments: commandlineArguments,
            environmentVariables: environments
        )
    }

    /// Returns the scheme analyze action.
    ///
    /// - Parameters:
    ///     - scheme: Scheme manifest.
    ///     - graphTraverser: Graph traverser.
    ///     - rootPath: Root path to either project or workspace.
    ///     - generatedProjects: Project paths mapped to generated projects.
    /// - Returns: Scheme analyze action.
    func schemeAnalyzeAction(
        scheme: Scheme,
        graphTraverser: GraphTraversing,
        rootPath _: AbsolutePath,
        generatedProjects _: [AbsolutePath: GeneratedProject]
    ) throws -> XCScheme.AnalyzeAction? {
        guard let target = defaultTargetReference(scheme: scheme),
              let graphTarget = graphTraverser.target(path: target.projectPath, name: target.name) else { return nil }

        let buildConfiguration = scheme.analyzeAction?.configurationName ?? graphTarget.project.defaultDebugBuildConfigurationName
        return XCScheme.AnalyzeAction(buildConfiguration: buildConfiguration)
    }

    /// Generates the scheme archive action.
    ///
    /// - Parameters:
    ///     - scheme: Scheme manifest.
    ///     - graphTraverser: Graph traverser.
    ///     - rootPath: Root path to either project or workspace.
    ///     - generatedProjects: Project paths mapped to generated projects.
    /// - Returns: Scheme archive action.
    func schemeArchiveAction(
        scheme: Scheme,
        graphTraverser: GraphTraversing,
        rootPath: AbsolutePath,
        generatedProjects: [AbsolutePath: GeneratedProject]
    ) throws -> XCScheme.ArchiveAction? {
        guard let archiveAction = scheme.archiveAction else {
            guard let target = defaultTargetReference(scheme: scheme),
                  let graphTarget = graphTraverser.target(path: target.projectPath, name: target.name)
            else {
                return nil
            }
            return defaultSchemeArchiveAction(for: graphTarget.project)
        }

        let preActions = try archiveAction.preActions.map {
            try schemeExecutionAction(
                action: $0,
                graphTraverser: graphTraverser,
                generatedProjects: generatedProjects,
                rootPath: rootPath
            )
        }

        let postActions = try archiveAction.postActions.map {
            try schemeExecutionAction(
                action: $0,
                graphTraverser: graphTraverser,
                generatedProjects: generatedProjects,
                rootPath: rootPath
            )
        }

        return XCScheme.ArchiveAction(
            buildConfiguration: archiveAction.configurationName,
            revealArchiveInOrganizer: archiveAction.revealArchiveInOrganizer,
            customArchiveName: archiveAction.customArchiveName,
            preActions: preActions,
            postActions: postActions
        )
    }

    func schemeExecutionAction(
        action: ExecutionAction,
        graphTraverser: GraphTraversing,
        generatedProjects: [AbsolutePath: GeneratedProject],
        rootPath: AbsolutePath
    ) throws -> XCScheme.ExecutionAction {
        guard let targetReference = action.target,
              let graphTarget = graphTraverser.target(path: targetReference.projectPath, name: targetReference.name)
        else {
            return XCScheme.ExecutionAction(
                scriptText: action.scriptText,
                title: action.title,
                shellToInvoke: action.shellPath,
                environmentBuildable: nil
            )
        }

        let buildableReference = try createBuildableReference(
            graphTarget: graphTarget,
            graphTraverser: graphTraverser,
            rootPath: rootPath,
            generatedProjects: generatedProjects
        )

        return XCScheme.ExecutionAction(
            scriptText: action.scriptText,
            title: action.title,
            shellToInvoke: action.shellPath,
            environmentBuildable: buildableReference
        )
    }

    // MARK: - Helpers

    private func resolveRelativeProjectPath(
        graphTarget: GraphTarget,
        generatedProject _: GeneratedProject,
        rootPath: AbsolutePath
    ) -> RelativePath {
        let xcodeProjectPath = graphTarget.project.xcodeProjPath
        return xcodeProjectPath.relative(to: rootPath)
    }

    /// Creates a target buildable refernece for a target
    ///
    /// - Parameters:
    ///     - graphTarget: The graph target.
    ///     - graphTraverser: Tuist graph traverser.
    ///     - rootPath: Path to the project or workspace.
    ///     - generatedProjects: Project paths mapped to generated projects.
    private func createBuildableReference(
        graphTarget: GraphTarget,
        graphTraverser: GraphTraversing,
        rootPath: AbsolutePath,
        generatedProjects: [AbsolutePath: GeneratedProject]
    ) throws -> XCScheme.BuildableReference? {
        let projectPath = graphTarget.project.xcodeProjPath
        guard let target = graphTraverser.target(path: graphTarget.project.path, name: graphTarget.target.name)
        else { return nil }
        guard let generatedProject = generatedProjects[projectPath] else { return nil }
        guard let pbxTarget = generatedProject.targets[graphTarget.target.name] else { return nil }
        let relativeXcodeProjectPath = resolveRelativeProjectPath(
            graphTarget: graphTarget,
            generatedProject: generatedProject,
            rootPath: rootPath
        )

        return targetBuildableReference(
            target: target.target,
            pbxTarget: pbxTarget,
            projectPath: relativeXcodeProjectPath.pathString
        )
    }

    /// Generates the array of BuildableReference for targets that the
    /// coverage report should be generated for them.
    ///
    /// - Parameters:
    ///   - graphTarget: The graph target.
    ///   - graphTraverser: Tuist graph traverser.
    ///   - generatedProjects: Generated Xcode projects.
    ///   - rootPath: Root path to workspace or project.
    /// - Returns: Array of buildable references.
    private func testCoverageTargetReferences(
        graphTarget: GraphTarget,
        graphTraverser: GraphTraversing,
        generatedProjects: [AbsolutePath: GeneratedProject],
        rootPath: AbsolutePath
    ) throws -> XCScheme.BuildableReference? {
        try createBuildableReference(
            graphTarget: graphTarget,
            graphTraverser: graphTraverser,
            rootPath: rootPath,
            generatedProjects: generatedProjects
        )
    }

    /// Returns the scheme commandline argument passed on launch
    ///
    /// - Parameters:
    ///     - arguments: commandline argument keys.
    /// - Returns: XCScheme.CommandLineArguments.CommandLineArgument.
    private func getCommandlineArguments(_ arguments: [LaunchArgument]) -> [XCScheme.CommandLineArguments.CommandLineArgument] {
        arguments.map {
            XCScheme.CommandLineArguments.CommandLineArgument(name: $0.name, enabled: $0.isEnabled)
        }
    }

    /// Returns the scheme environment variables
    ///
    /// - Parameters:
    ///     - environments: environment variables
    /// - Returns: XCScheme.EnvironmentVariable.
    private func environmentVariables(_ environments: [String: EnvironmentVariable]) -> [XCScheme.EnvironmentVariable] {
        environments.map { key, variable in
            XCScheme.EnvironmentVariable(variable: key, value: variable.value, enabled: variable.isEnabled)
        }.sorted { $0.variable < $1.variable }
    }

    /// Returns the scheme buildable reference for a given target.
    ///
    /// - Parameters:
    ///   - target: Target manifest.
    ///   - pbxTarget: Xcode native target.
    ///   - projectPath: Project name with the .xcodeproj extension.
    /// - Returns: Buildable reference.
    private func targetBuildableReference(
        target: Target,
        pbxTarget: PBXNativeTarget,
        projectPath: String
    ) -> XCScheme.BuildableReference {
        XCScheme.BuildableReference(
            referencedContainer: "container:\(projectPath)",
            blueprint: pbxTarget,
            buildableName: target.productNameWithExtension,
            blueprintName: target.name,
            buildableIdentifier: "primary"
        )
    }

    /// Returns the scheme archive action
    ///
    /// - Returns: Scheme archive action.
    func defaultSchemeArchiveAction(for project: Project) -> XCScheme.ArchiveAction {
        let buildConfiguration = defaultReleaseBuildConfigurationName(in: project)
        return XCScheme.ArchiveAction(
            buildConfiguration: buildConfiguration,
            revealArchiveInOrganizer: true
        )
    }

    private func defaultReleaseBuildConfigurationName(in project: Project) -> String {
        let releaseConfiguration = project.settings.defaultReleaseBuildConfiguration()
        let buildConfiguration = releaseConfiguration ?? project.settings.configurations.keys.first

        return buildConfiguration?.name ?? BuildConfiguration.release.name
    }

    private func defaultTargetReference(scheme: Scheme) -> TargetReference? {
        scheme.buildAction?.targets.first
    }

    private func isSchemeForAppExtension(scheme: Scheme, graphTraverser: GraphTraversing) -> Bool? {
        guard let defaultTarget = defaultTargetReference(scheme: scheme),
              let graphTarget = graphTraverser.target(path: defaultTarget.projectPath, name: defaultTarget.name)
        else {
            return nil
        }

        switch graphTarget.target.product {
        case .appExtension, .messagesExtension, .extensionKitExtension:
            return true
        default:
            return nil
        }
    }
}

extension TestAction {
    fileprivate static func empty(withConfigurationName configurationName: String) -> Self {
        .init(
            targets: [],
            arguments: nil,
            configurationName: configurationName,
            attachDebugger: true,
            coverage: false,
            codeCoverageTargets: [],
            expandVariableFromTarget: nil,
            preActions: [],
            postActions: [],
            diagnosticsOptions: SchemeDiagnosticsOptions(),
            language: nil,
            region: nil,
            preferredScreenCaptureFormat: nil,
            testPlans: nil
        )
    }
}
