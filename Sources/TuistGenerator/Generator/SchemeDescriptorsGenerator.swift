import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XcodeProj

/// Protocol that defines the interface of the schemes generation.
protocol SchemeDescriptorsGenerating {
    /// Generates the schemes for the workspace targets.
    ///
    /// - Parameters:
    ///   - workspace: Workspace model.
    ///   - xcworkspacePath: Path to the workspace.
    ///   - generatedProject: Generated Xcode project.
    ///   - graphTraverser: Graph traverser.
    /// - Throws: A FatalError if the generation of the schemes fails.
    func generateWorkspaceSchemes(workspace: Workspace,
                                  generatedProjects: [AbsolutePath: GeneratedProject],
                                  graphTraverser: GraphTraversing) throws -> [SchemeDescriptor]

    /// Generates the schemes for the project targets.
    ///
    /// - Parameters:
    ///   - project: Project manifest.
    ///   - xcprojectPath: Path to the Xcode project.
    ///   - generatedProject: Generated Xcode project.
    ///   - graphTraverser: Graph traverser.
    /// - Throws: A FatalError if the generation of the schemes fails.
    func generateProjectSchemes(project: Project,
                                generatedProject: GeneratedProject,
                                graphTraverser: GraphTraversing) throws -> [SchemeDescriptor]
}

// swiftlint:disable:next type_body_length
final class SchemeDescriptorsGenerator: SchemeDescriptorsGenerating {
    private struct Constants {
        /// Default last upgrade version for generated schemes.
        static let defaultLastUpgradeVersion = "1010"

        /// Default version for generated schemes.
        static let defaultVersion = "1.3"

        struct LaunchAction {
            var debugger: String
            var launcher: String
            var askForAppToLaunch: Bool?
            var launchAutomaticallySubstyle: String?

            static var `default`: LaunchAction {
                LaunchAction(debugger: XCScheme.defaultDebugger,
                             launcher: XCScheme.defaultLauncher,
                             askForAppToLaunch: nil,
                             launchAutomaticallySubstyle: nil)
            }

            static var `extension`: LaunchAction {
                LaunchAction(debugger: "",
                             launcher: "Xcode.IDEFoundation.Launcher.PosixSpawn",
                             askForAppToLaunch: true,
                             launchAutomaticallySubstyle: "2")
            }
        }
    }

    func generateWorkspaceSchemes(workspace: Workspace,
                                  generatedProjects: [AbsolutePath: GeneratedProject],
                                  graphTraverser: GraphTraversing) throws -> [SchemeDescriptor]
    {
        let schemes = try workspace.schemes.map { scheme in
            try generateScheme(scheme: scheme,
                               path: workspace.xcWorkspacePath.parentDirectory,
                               graphTraverser: graphTraverser,
                               generatedProjects: generatedProjects)
        }

        return schemes
    }

    func generateProjectSchemes(project: Project,
                                generatedProject: GeneratedProject,
                                graphTraverser: GraphTraversing) throws -> [SchemeDescriptor]
    {
        try project.schemes.map { scheme in
            try generateScheme(scheme: scheme,
                               path: project.xcodeProjPath.parentDirectory,
                               graphTraverser: graphTraverser,
                               generatedProjects: [project.xcodeProjPath: generatedProject])
        }
    }

    /// Wipes shared and user schemes at a workspace or project path. This is needed
    /// currently to support the workspace scheme generation case where a workspace that
    /// already exists on disk is being regenerated. Wiping the schemes directory prevents
    /// older custom schemes from persisting after regeneration.
    ///
    /// - Parameter at: Path to the workspace or project.
    func wipeSchemes(at path: AbsolutePath) throws {
        let fileHandler = FileHandler.shared
        let userPath = schemeDirectory(path: path, shared: false)
        let sharedPath = schemeDirectory(path: path, shared: true)
        if fileHandler.exists(userPath) { try fileHandler.delete(userPath) }
        if fileHandler.exists(sharedPath) { try fileHandler.delete(sharedPath) }
    }

    /// Generate schemes for a project or workspace.
    ///
    /// - Parameters:
    ///     - scheme: Project scheme.
    ///     - xcPath: Path to workspace's .xcworkspace or project's .xcodeproj.
    ///     - path: Path to workspace or project folder.
    ///     - graphTraverser: Graph traverser.
    ///     - generatedProjects: Project paths mapped to generated projects.
    private func generateScheme(scheme: Scheme,
                                path: AbsolutePath,
                                graphTraverser: GraphTraversing,
                                generatedProjects: [AbsolutePath: GeneratedProject]) throws -> SchemeDescriptor
    {
        let generatedBuildAction = try schemeBuildAction(scheme: scheme,
                                                         graphTraverser: graphTraverser,
                                                         rootPath: path,
                                                         generatedProjects: generatedProjects)
        let generatedTestAction = try schemeTestAction(scheme: scheme,
                                                       graphTraverser: graphTraverser,
                                                       rootPath: path,
                                                       generatedProjects: generatedProjects)
        let generatedLaunchAction = try schemeLaunchAction(scheme: scheme,
                                                           graphTraverser: graphTraverser,
                                                           rootPath: path,
                                                           generatedProjects: generatedProjects)
        let generatedProfileAction = try schemeProfileAction(scheme: scheme,
                                                             graphTraverser: graphTraverser,
                                                             rootPath: path,
                                                             generatedProjects: generatedProjects)
        let generatedAnalyzeAction = try schemeAnalyzeAction(scheme: scheme,
                                                             graphTraverser: graphTraverser,
                                                             rootPath: path,
                                                             generatedProjects: generatedProjects)
        let generatedArchiveAction = try schemeArchiveAction(scheme: scheme,
                                                             graphTraverser: graphTraverser,
                                                             rootPath: path,
                                                             generatedProjects: generatedProjects)

        let wasCreatedForAppExtension = isSchemeForAppExtension(scheme: scheme, graphTraverser: graphTraverser)

        let xcscheme = XCScheme(name: scheme.name,
                                lastUpgradeVersion: Constants.defaultLastUpgradeVersion,
                                version: Constants.defaultVersion,
                                buildAction: generatedBuildAction,
                                testAction: generatedTestAction,
                                launchAction: generatedLaunchAction,
                                profileAction: generatedProfileAction,
                                analyzeAction: generatedAnalyzeAction,
                                archiveAction: generatedArchiveAction,
                                wasCreatedForAppExtension: wasCreatedForAppExtension)

        return SchemeDescriptor(xcScheme: xcscheme, shared: scheme.shared)
    }

    /// Generates the scheme build action.
    ///
    /// - Parameters:
    ///   - scheme: Scheme manifest.
    ///   - graphTraverser: Graph traverser.
    ///   - rootPath: Path to the project or workspace.
    ///   - generatedProjects: Project paths mapped to generated projects.
    /// - Returns: Scheme build action.
    func schemeBuildAction(scheme: Scheme,
                           graphTraverser: GraphTraversing,
                           rootPath: AbsolutePath,
                           generatedProjects: [AbsolutePath: GeneratedProject]) throws -> XCScheme.BuildAction?
    {
        guard let buildAction = scheme.buildAction else { return nil }

        let buildFor: [XCScheme.BuildAction.Entry.BuildFor] = [
            .analyzing, .archiving, .profiling, .running, .testing,
        ]

        var entries: [XCScheme.BuildAction.Entry] = []
        var preActions: [XCScheme.ExecutionAction] = []
        var postActions: [XCScheme.ExecutionAction] = []

        try buildAction.targets.forEach { buildActionTarget in
            guard let buildActionGraphTarget = graphTraverser.target(path: buildActionTarget.projectPath, name: buildActionTarget.name) else { return }
            guard let buildableReference = try createBuildableReference(graphTarget: buildActionGraphTarget,
                                                                        graphTraverser: graphTraverser,
                                                                        rootPath: rootPath,
                                                                        generatedProjects: generatedProjects) else { return }
            entries.append(XCScheme.BuildAction.Entry(buildableReference: buildableReference, buildFor: buildFor))
        }

        preActions = try buildAction.preActions.map {
            try schemeExecutionAction(action: $0, graphTraverser: graphTraverser, generatedProjects: generatedProjects, rootPath: rootPath)
        }

        postActions = try buildAction.postActions.map {
            try schemeExecutionAction(action: $0, graphTraverser: graphTraverser, generatedProjects: generatedProjects, rootPath: rootPath)
        }

        return XCScheme.BuildAction(buildActionEntries: entries,
                                    preActions: preActions,
                                    postActions: postActions,
                                    parallelizeBuild: true,
                                    buildImplicitDependencies: true)
    }

    /// Generates the scheme test action.
    ///
    /// - Parameters:
    ///   - scheme: Scheme manifest.
    ///   - graphTraverser: Graph traverser.
    ///   - rootPath: Root path to either project or workspace.
    ///   - generatedProjects: Project paths mapped to generated projects.
    /// - Returns: Scheme test action.
    // swiftlint:disable:next function_body_length
    func schemeTestAction(scheme: Scheme,
                          graphTraverser: GraphTraversing,
                          rootPath: AbsolutePath,
                          generatedProjects: [AbsolutePath: GeneratedProject]) throws -> XCScheme.TestAction?
    {
        guard let testAction = scheme.testAction else { return nil }

        var testables: [XCScheme.TestableReference] = []
        var preActions: [XCScheme.ExecutionAction] = []
        var postActions: [XCScheme.ExecutionAction] = []

        let testPlans: [XCScheme.TestPlanReference]? = testAction.testPlans?.map {
            XCScheme.TestPlanReference(reference: "container:\($0.path.relative(to: rootPath))",
                                       default: $0.isDefault)
        }

        try testAction.targets.forEach { testableTarget in
            guard let testableGraphTarget = graphTraverser.target(path: testableTarget.target.projectPath, name: testableTarget.target.name) else { return }
            guard let reference = try createBuildableReference(graphTarget: testableGraphTarget,
                                                               graphTraverser: graphTraverser,
                                                               rootPath: rootPath,
                                                               generatedProjects: generatedProjects) else { return }
            let testable = XCScheme.TestableReference(skipped: testableTarget.isSkipped,
                                                      parallelizable: testableTarget.isParallelizable,
                                                      randomExecutionOrdering: testableTarget.isRandomExecutionOrdering,
                                                      buildableReference: reference)
            testables.append(testable)
        }

        preActions = try testAction.preActions.map { try schemeExecutionAction(action: $0,
                                                                               graphTraverser: graphTraverser,
                                                                               generatedProjects: generatedProjects,
                                                                               rootPath: rootPath) }
        postActions = try testAction.postActions.map { try schemeExecutionAction(action: $0,
                                                                                 graphTraverser: graphTraverser,
                                                                                 generatedProjects: generatedProjects,
                                                                                 rootPath: rootPath) }

        var args: XCScheme.CommandLineArguments?
        var environments: [XCScheme.EnvironmentVariable]?

        if let arguments = testAction.arguments {
            args = XCScheme.CommandLineArguments(arguments: commandlineArgruments(arguments.launchArguments))
            environments = environmentVariables(arguments.environment)
        }

        let codeCoverageTargets = try testAction.codeCoverageTargets.compactMap { (target: TargetReference) -> XCScheme.BuildableReference? in
            guard let graphTarget = graphTraverser.target(path: target.projectPath, name: target.name) else { return nil }
            return try testCoverageTargetReferences(graphTarget: graphTarget,
                                                    graphTraverser: graphTraverser,
                                                    generatedProjects: generatedProjects,
                                                    rootPath: rootPath)
        }

        let onlyGenerateCoverageForSpecifiedTargets = codeCoverageTargets.count > 0 ? true : nil

        let disableMainThreadChecker = !testAction.diagnosticsOptions.contains(.mainThreadChecker)
        let shouldUseLaunchSchemeArgsEnv: Bool = args == nil && environments == nil
        let language = testAction.language
        let region = testAction.region

        return XCScheme.TestAction(buildConfiguration: testAction.configurationName,
                                   macroExpansion: nil,
                                   testables: testables,
                                   testPlans: testPlans,
                                   preActions: preActions,
                                   postActions: postActions,
                                   shouldUseLaunchSchemeArgsEnv: shouldUseLaunchSchemeArgsEnv,
                                   codeCoverageEnabled: testAction.coverage,
                                   codeCoverageTargets: codeCoverageTargets,
                                   onlyGenerateCoverageForSpecifiedTargets: onlyGenerateCoverageForSpecifiedTargets,
                                   disableMainThreadChecker: disableMainThreadChecker,
                                   commandlineArguments: args,
                                   environmentVariables: environments,
                                   language: language,
                                   region: region)
    }

    /// Generates the scheme launch action.
    ///
    /// - Parameters:
    ///   - scheme: Scheme manifest.
    ///   - graphTraverser: Graph traverser.
    ///   - rootPath: Root path to either project or workspace.
    ///   - generatedProjects: Project paths mapped to generated projects.
    /// - Returns: Scheme launch action.
    func schemeLaunchAction(scheme: Scheme,
                            graphTraverser: GraphTraversing,
                            rootPath: AbsolutePath,
                            generatedProjects: [AbsolutePath: GeneratedProject]) throws -> XCScheme.LaunchAction?
    {
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
            guard let buildableReference = try createBuildableReference(graphTarget: graphTarget,
                                                                        graphTraverser: graphTraverser,
                                                                        rootPath: rootPath,
                                                                        generatedProjects: generatedProjects) else { return nil }

            if graphTarget.target.product.runnable {
                buildableProductRunnable = XCScheme.BuildableProductRunnable(buildableReference: buildableReference, runnableDebuggingMode: "0")
            } else {
                macroExpansion = buildableReference
            }
        }

        var commandlineArguments: XCScheme.CommandLineArguments?
        var environments: [XCScheme.EnvironmentVariable]?
        var storeKitConfigurationFileReference: XCScheme.StoreKitConfigurationFileReference?

        if let arguments = scheme.runAction?.arguments {
            commandlineArguments = XCScheme.CommandLineArguments(arguments: commandlineArgruments(arguments.launchArguments))
            environments = environmentVariables(arguments.environment)
        }

        let buildConfiguration = scheme.runAction?.configurationName ?? defaultBuildConfiguration
        let disableMainThreadChecker = scheme.runAction?.diagnosticsOptions.contains(.mainThreadChecker) == false
        let isSchemeForAppExtension = self.isSchemeForAppExtension(scheme: scheme, graphTraverser: graphTraverser)
        let launchActionConstants: Constants.LaunchAction = isSchemeForAppExtension == true ? .extension : .default

        if
            let storeKitFilePath = scheme.runAction?.options.storeKitConfigurationPath,
            let graphTarget = graphTraverser.target(path: target.projectPath, name: target.name)
        {
            // the identifier is the relative path between the storekit file, and the xcode project
            let fileRelativePath = storeKitFilePath.relative(to: graphTarget.project.xcodeProjPath)
            storeKitConfigurationFileReference = .init(identifier: fileRelativePath.pathString)
        }

        return XCScheme.LaunchAction(runnable: buildableProductRunnable,
                                     buildConfiguration: buildConfiguration,
                                     macroExpansion: macroExpansion,
                                     selectedDebuggerIdentifier: launchActionConstants.debugger,
                                     selectedLauncherIdentifier: launchActionConstants.launcher,
                                     askForAppToLaunch: launchActionConstants.askForAppToLaunch,
                                     pathRunnable: pathRunnable,
                                     disableMainThreadChecker: disableMainThreadChecker,
                                     commandlineArguments: commandlineArguments,
                                     environmentVariables: environments,
                                     launchAutomaticallySubstyle: launchActionConstants.launchAutomaticallySubstyle,
                                     storeKitConfigurationFileReference: storeKitConfigurationFileReference)
    }

    /// Generates the scheme profile action for a given target.
    ///
    /// - Parameters:
    ///   - scheme: Target manifest.
    ///   - graphTraverser: Graph traverser.
    ///   - rootPath: Root path to either project or workspace.
    ///   - generatedProjects: Project paths mapped to generated projects.
    /// - Returns: Scheme profile action.
    func schemeProfileAction(scheme: Scheme,
                             graphTraverser: GraphTraversing,
                             rootPath: AbsolutePath,
                             generatedProjects: [AbsolutePath: GeneratedProject]) throws -> XCScheme.ProfileAction?
    {
        guard var target = defaultTargetReference(scheme: scheme) else { return nil }
        var commandlineArguments: XCScheme.CommandLineArguments?
        var environments: [XCScheme.EnvironmentVariable]?

        if let action = scheme.profileAction, let executable = action.executable {
            target = executable
            if let arguments = action.arguments {
                commandlineArguments = XCScheme.CommandLineArguments(arguments: commandlineArgruments(arguments.launchArguments))
                environments = environmentVariables(arguments.environment)
            }
        } else if let action = scheme.runAction, let executable = action.executable {
            target = executable
            // arguments are inherited automatically from Launch Action (via `shouldUseLaunchSchemeArgsEnv`)
        }

        let shouldUseLaunchSchemeArgsEnv: Bool = commandlineArguments == nil && environments == nil

        guard let graphTarget = graphTraverser.target(path: target.projectPath, name: target.name) else { return nil }
        guard let buildableReference = try createBuildableReference(graphTarget: graphTarget,
                                                                    graphTraverser: graphTraverser,
                                                                    rootPath: rootPath,
                                                                    generatedProjects: generatedProjects) else { return nil }

        var buildableProductRunnable: XCScheme.BuildableProductRunnable?
        var macroExpansion: XCScheme.BuildableReference?

        if graphTarget.target.product.runnable {
            buildableProductRunnable = XCScheme.BuildableProductRunnable(buildableReference: buildableReference, runnableDebuggingMode: "0")
        } else {
            macroExpansion = buildableReference
        }

        let buildConfiguration = scheme.profileAction?.configurationName ?? defaultReleaseBuildConfigurationName(in: graphTarget.project)
        return XCScheme.ProfileAction(buildableProductRunnable: buildableProductRunnable,
                                      buildConfiguration: buildConfiguration,
                                      macroExpansion: macroExpansion,
                                      shouldUseLaunchSchemeArgsEnv: shouldUseLaunchSchemeArgsEnv,
                                      commandlineArguments: commandlineArguments,
                                      environmentVariables: environments)
    }

    /// Returns the scheme analyze action.
    ///
    /// - Parameters:
    ///     - scheme: Scheme manifest.
    ///     - graphTraverser: Graph traverser.
    ///     - rootPath: Root path to either project or workspace.
    ///     - generatedProjects: Project paths mapped to generated projects.
    /// - Returns: Scheme analyze action.
    func schemeAnalyzeAction(scheme: Scheme,
                             graphTraverser: GraphTraversing,
                             rootPath _: AbsolutePath,
                             generatedProjects _: [AbsolutePath: GeneratedProject]) throws -> XCScheme.AnalyzeAction?
    {
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
    func schemeArchiveAction(scheme: Scheme,
                             graphTraverser: GraphTraversing,
                             rootPath: AbsolutePath,
                             generatedProjects: [AbsolutePath: GeneratedProject]) throws -> XCScheme.ArchiveAction?
    {
        guard let target = defaultTargetReference(scheme: scheme),
            let graphTarget = graphTraverser.target(path: target.projectPath, name: target.name) else { return nil }

        guard let archiveAction = scheme.archiveAction else {
            return defaultSchemeArchiveAction(for: graphTarget.project)
        }

        let preActions = try archiveAction.preActions.map {
            try schemeExecutionAction(action: $0, graphTraverser: graphTraverser, generatedProjects: generatedProjects, rootPath: rootPath)
        }

        let postActions = try archiveAction.postActions.map {
            try schemeExecutionAction(action: $0, graphTraverser: graphTraverser, generatedProjects: generatedProjects, rootPath: rootPath)
        }

        return XCScheme.ArchiveAction(buildConfiguration: archiveAction.configurationName,
                                      revealArchiveInOrganizer: archiveAction.revealArchiveInOrganizer,
                                      customArchiveName: archiveAction.customArchiveName,
                                      preActions: preActions,
                                      postActions: postActions)
    }

    func schemeExecutionAction(action: ExecutionAction,
                               graphTraverser: GraphTraversing,
                               generatedProjects: [AbsolutePath: GeneratedProject],
                               rootPath _: AbsolutePath) throws -> XCScheme.ExecutionAction
    {
        guard
            let targetReference = action.target,
            let graphTarget = graphTraverser.target(path: targetReference.projectPath, name: targetReference.name),
            let generatedProject = generatedProjects[graphTarget.project.xcodeProjPath]
        else {
            return schemeExecutionAction(action: action)
        }
        return schemeExecutionAction(action: action,
                                     target: graphTarget.target,
                                     generatedProject: generatedProject)
    }

    private func schemeExecutionAction(action: ExecutionAction) -> XCScheme.ExecutionAction {
        XCScheme.ExecutionAction(scriptText: action.scriptText,
                                 title: action.title,
                                 environmentBuildable: nil)
    }

    /// Returns the scheme pre/post actions.
    ///
    /// - Parameters:
    ///   - action: pre/post action manifest.
    ///   - target: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    /// - Returns: Scheme actions.
    private func schemeExecutionAction(action: ExecutionAction,
                                       target: Target,
                                       generatedProject: GeneratedProject) -> XCScheme.ExecutionAction
    {
        /// Return Buildable Reference for Scheme Action
        func schemeBuildableReference(target: Target, generatedProject: GeneratedProject) -> XCScheme.BuildableReference? {
            guard let pbxTarget = generatedProject.targets[target.name] else { return nil }

            return targetBuildableReference(target: target,
                                            pbxTarget: pbxTarget,
                                            projectPath: generatedProject.name)
        }

        let schemeAction = XCScheme.ExecutionAction(scriptText: action.scriptText,
                                                    title: action.title,
                                                    environmentBuildable: nil)

        schemeAction.environmentBuildable = schemeBuildableReference(target: target,
                                                                     generatedProject: generatedProject)
        return schemeAction
    }

    // MARK: - Helpers

    private func resolveRelativeProjectPath(graphTarget: ValueGraphTarget,
                                            generatedProject _: GeneratedProject,
                                            rootPath: AbsolutePath) -> RelativePath
    {
        let xcodeProjectPath = graphTarget.project.xcodeProjPath
        return xcodeProjectPath.relative(to: rootPath)
    }

    /// Creates a target buildable refernece for a target
    ///
    /// - Parameters:
    ///     - graphTarget: The graph target.
    ///     - graph: Tuist graph.
    ///     - rootPath: Path to the project or workspace.
    ///     - generatedProjects: Project paths mapped to generated projects.
    private func createBuildableReference(graphTarget: ValueGraphTarget,
                                          graphTraverser: GraphTraversing,
                                          rootPath: AbsolutePath,
                                          generatedProjects: [AbsolutePath: GeneratedProject]) throws -> XCScheme.BuildableReference?
    {
        let projectPath = graphTarget.project.xcodeProjPath
        guard let target = graphTraverser.target(path: graphTarget.project.path, name: graphTarget.target.name) else { return nil }
        guard let generatedProject = generatedProjects[projectPath] else { return nil }
        guard let pbxTarget = generatedProject.targets[graphTarget.target.name] else { return nil }
        let relativeXcodeProjectPath = resolveRelativeProjectPath(graphTarget: graphTarget,
                                                                  generatedProject: generatedProject,
                                                                  rootPath: rootPath)

        return targetBuildableReference(target: target.target,
                                        pbxTarget: pbxTarget,
                                        projectPath: relativeXcodeProjectPath.pathString)
    }

    /// Generates the array of BuildableReference for targets that the
    /// coverage report should be generated for them.
    ///
    /// - Parameters:
    ///   - target: test actions.
    ///   - graph: tuist graph.
    ///   - generatedProjects: Generated Xcode projects.
    ///   - rootPath: Root path to workspace or project.
    /// - Returns: Array of buildable references.
    private func testCoverageTargetReferences(graphTarget: ValueGraphTarget,
                                              graphTraverser: GraphTraversing,
                                              generatedProjects: [AbsolutePath: GeneratedProject],
                                              rootPath: AbsolutePath) throws -> XCScheme.BuildableReference?
    {
        try createBuildableReference(graphTarget: graphTarget,
                                     graphTraverser: graphTraverser,
                                     rootPath: rootPath,
                                     generatedProjects: generatedProjects)
    }

    /// Creates the directory where the schemes are stored inside the project.
    /// If the directory exists it does not re-create it.
    ///
    /// - Parameters:
    ///   - path: Path to the Xcode workspace or project.
    ///   - shared: Scheme should be shared or not
    /// - Returns: Path to the schemes directory.
    /// - Throws: A FatalError if the creation of the directory fails.
    private func createSchemesDirectory(path: AbsolutePath, shared: Bool = true) throws -> AbsolutePath {
        let schemePath = schemeDirectory(path: path, shared: shared)
        if !FileHandler.shared.exists(schemePath) {
            try FileHandler.shared.createFolder(schemePath)
        }
        return schemePath
    }

    private func schemeDirectory(path: AbsolutePath, shared: Bool = true) -> AbsolutePath {
        if shared {
            return path.appending(RelativePath("xcshareddata/xcschemes"))
        } else {
            let username = NSUserName()
            return path.appending(RelativePath("xcuserdata/\(username).xcuserdatad/xcschemes"))
        }
    }

    /// Returns the scheme commandline argument passed on launch
    ///
    /// - Parameters:
    ///     - environments: commandline argument keys.
    /// - Returns: XCScheme.CommandLineArguments.CommandLineArgument.
    private func commandlineArgruments(_ arguments: [LaunchArgument]) -> [XCScheme.CommandLineArguments.CommandLineArgument] {
        arguments.map {
            XCScheme.CommandLineArguments.CommandLineArgument(name: $0.name, enabled: $0.isEnabled)
        }
    }

    /// Returns the scheme environment variables
    ///
    /// - Parameters:
    ///     - environments: environment variables
    /// - Returns: XCScheme.EnvironmentVariable.
    private func environmentVariables(_ environments: [String: String]) -> [XCScheme.EnvironmentVariable] {
        environments.map { key, value in
            XCScheme.EnvironmentVariable(variable: key, value: value, enabled: true)
        }.sorted { $0.variable < $1.variable }
    }

    /// Returns the scheme buildable reference for a given target.
    ///
    /// - Parameters:
    ///   - target: Target manifest.
    ///   - pbxTarget: Xcode native target.
    ///   - projectPath: Project name with the .xcodeproj extension.
    /// - Returns: Buildable reference.
    private func targetBuildableReference(target: Target,
                                          pbxTarget: PBXNativeTarget,
                                          projectPath: String) -> XCScheme.BuildableReference
    {
        XCScheme.BuildableReference(referencedContainer: "container:\(projectPath)",
                                    blueprint: pbxTarget,
                                    buildableName: target.productNameWithExtension,
                                    blueprintName: target.name,
                                    buildableIdentifier: "primary")
    }

    /// Returns the scheme archive action
    ///
    /// - Returns: Scheme archive action.
    func defaultSchemeArchiveAction(for project: Project) -> XCScheme.ArchiveAction {
        let buildConfiguration = defaultReleaseBuildConfigurationName(in: project)
        return XCScheme.ArchiveAction(buildConfiguration: buildConfiguration,
                                      revealArchiveInOrganizer: true)
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
        case .appExtension, .messagesExtension:
            return true
        default:
            return nil
        }
    }
}
