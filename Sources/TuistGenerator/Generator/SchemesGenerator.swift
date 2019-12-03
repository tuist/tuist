import Basic
import Foundation
import TuistCore
import TuistSupport
import XcodeProj

/// Protocol that defines the interface of the schemes generation.
protocol SchemesGenerating {
    /// Generates the schemes for the workspace targets.
    ///
    /// - Parameters:
    ///   - workspace: Workspace model.
    ///   - xcworkspacePath: Path to the workspace.
    ///   - generatedProject: Generated Xcode project.
    ///   - graph: Tuist graph.
    /// - Throws: A FatalError if the generation of the schemes fails.
    func generateWorkspaceSchemes(workspace: Workspace,
                                  xcworkspacePath: AbsolutePath,
                                  generatedProjects: [AbsolutePath: GeneratedProject],
                                  graph: Graphing) throws
    
    /// Generates the schemes for the project targets.
    ///
    /// - Parameters:
    ///   - project: Project manifest.
    ///   - xcprojectPath: Path to the Xcode project.
    ///   - generatedProject: Generated Xcode project.
    ///   - graph: Tuist graph.
    /// - Throws: A FatalError if the generation of the schemes fails.
    func generateProjectSchemes(project: Project,
                                xcprojectPath: AbsolutePath,
                                generatedProject: GeneratedProject,
                                graph: Graphing) throws
}

// swiftlint:disable:next type_body_length
final class SchemesGenerator: SchemesGenerating {
    /// Default last upgrade version for generated schemes.
    private static let defaultLastUpgradeVersion = "1010"

    /// Default version for generated schemes.
    private static let defaultVersion = "1.3"
    
    /// Generates the schemes for the workspace targets.
    ///
    /// - Parameters:
    ///   - workspace: Workspace model.
    ///   - xcworkspacePath: Path to the workspace.
    ///   - generatedProject: Generated Xcode project.
    ///   - graph: Tuist graph.
    /// - Throws: A FatalError if the generation of the schemes fails.
    func generateWorkspaceSchemes(workspace: Workspace,
                                  xcworkspacePath: AbsolutePath,
                                  generatedProjects: [AbsolutePath: GeneratedProject],
                                  graph: Graphing) throws {
        try workspace.schemes.forEach { scheme in
            try generateScheme(scheme: scheme,
                               xcPath: xcworkspacePath,
                               path: workspace.path,
                               graph: graph,
                               generatedProjects: generatedProjects)
        }
    }
    
    /// Generate schemes for a project.
    ///
    /// - Parameters:
    ///     - project: Project manifest.
    ///     - xcprojectPath: Path to project's .xcodeproj.
    ///     - generatedProject: Generated Project
    ///     - graph: Tuist graph.
    func generateProjectSchemes(project: Project,
                                xcprojectPath: AbsolutePath,
                                generatedProject: GeneratedProject,
                                graph: Graphing) throws {
        
        /// Generate custom schemes from manifest
        try project.schemes.forEach { scheme in
            try generateScheme(scheme: scheme,
                               xcPath: xcprojectPath,
                               path: project.path,
                               graph: graph,
                               generatedProjects: [project.path: generatedProject])
        }
        
        /// Generate default schemes for targets in Project that are not defined in Manifest
        let buildConfiguration = defaultDebugBuildConfigurationName(in: project)
        let userDefinedSchemes = Set(project.schemes.map(\.name))
        let defaultSchemeTargets = project.targets.filter { !userDefinedSchemes.contains($0.name) }
        try defaultSchemeTargets.forEach { target in
            let scheme = createDefaultScheme(target: target, project: project, buildConfiguration: buildConfiguration)
            try generateScheme(scheme: scheme,
                               xcPath: xcprojectPath,
                               path: project.path,
                               graph: graph,
                               generatedProjects: [project.path: generatedProject])

        }
    }
    
    private func createDefaultScheme(target: Target, project: Project, buildConfiguration: String) -> Scheme {
        let targetReference = TargetReference.project(path: project.path, target: target.name)
        let testTargets = target.product.testsBundle ? [TestableTarget(target: targetReference)] : []
        return Scheme(name: target.name,
                      shared: true,
                      buildAction: BuildAction(targets: [targetReference]),
                      testAction: TestAction(targets: testTargets, configurationName: buildConfiguration),
                      runAction: RunAction(configurationName: buildConfiguration, executable: targetReference, arguments: Arguments(environment: target.environment)))
    }
    
    /// Generate schemes for a project or workspace.
    ///
    /// - Parameters:
    ///     - scheme: Project scheme.
    ///     - xcPath: Path to workspace's .xcworkspace or project's .xcodeproj.
    ///     - path: Path to workspace or project folder.
    ///     - graph: Tuist graph.
    ///     - generatedProjects: Project paths mapped to generated projects.
    private func generateScheme(scheme: Scheme,
                                xcPath: AbsolutePath,
                                path: AbsolutePath,
                                graph: Graphing,
                                generatedProjects: [AbsolutePath: GeneratedProject]) throws {
        let schemeDirectory = try createSchemesDirectory(path: xcPath, shared: scheme.shared)
        let schemePath = schemeDirectory.appending(component: "\(scheme.name).xcscheme")
        
        let generatedBuildAction = try schemeBuildAction(scheme: scheme,
                                                         graph: graph,
                                                         rootPath: path,
                                                         generatedProjects: generatedProjects)
        let generatedTestAction = try schemeTestAction(scheme: scheme,
                                                       graph: graph,
                                                       rootPath: path,
                                                       generatedProjects: generatedProjects)
        let generatedLaunchAction = try schemeLaunchAction(scheme: scheme,
                                                           graph: graph,
                                                           rootPath: path,
                                                           generatedProjects: generatedProjects)
        let generatedProfileAction = try schemeProfileAction(scheme: scheme,
                                                             graph: graph,
                                                             rootPath: path,
                                                             generatedProjects: generatedProjects)
        let generatedAnalyzeAction = try schemeAnalyzeAction(scheme: scheme,
                                                             graph: graph,
                                                             rootPath: path,
                                                             generatedProjects: generatedProjects)
        let generatedArchiveAction = try schemeArchiveAction(scheme: scheme,
                                                             graph: graph,
                                                             rootPath: path,
                                                             generatedProjects: generatedProjects)

        let scheme = XCScheme(name: scheme.name,
                              lastUpgradeVersion: SchemesGenerator.defaultLastUpgradeVersion,
                              version: SchemesGenerator.defaultVersion,
                              buildAction: generatedBuildAction,
                              testAction: generatedTestAction,
                              launchAction: generatedLaunchAction,
                              profileAction: generatedProfileAction,
                              analyzeAction: generatedAnalyzeAction,
                              archiveAction: generatedArchiveAction)
                              
        try scheme.write(path: schemePath.path, override: true)
    }
    
    /// Generates the scheme build action.
    ///
    /// - Parameters:
    ///   - scheme: Scheme manifest.
    ///   - graph: Tuist graph.
    ///   - rootPath: Path to the project or workspace.
    ///   - generatedProjects: Project paths mapped to generated projects.
    /// - Returns: Scheme build action.
    func schemeBuildAction(scheme: Scheme,
                           graph: Graphing,
                           rootPath: AbsolutePath,
                           generatedProjects: [AbsolutePath: GeneratedProject]) throws -> XCScheme.BuildAction? {
        guard let buildAction = scheme.buildAction else { return nil }

        let buildFor: [XCScheme.BuildAction.Entry.BuildFor] = [
            .analyzing, .archiving, .profiling, .running, .testing,
        ]

        var entries: [XCScheme.BuildAction.Entry] = []
        var preActions: [XCScheme.ExecutionAction] = []
        var postActions: [XCScheme.ExecutionAction] = []

        try buildAction.targets.forEach { buildActionTarget in
            guard let buildableReference = try createBuildableReference(targetReference: buildActionTarget,
                                                                        graph: graph,
                                                                        rootPath: rootPath,
                                                                        generatedProjects: generatedProjects) else { return }
            entries.append(XCScheme.BuildAction.Entry(buildableReference: buildableReference, buildFor: buildFor))
        }
        
        preActions = try buildAction.preActions.map {
            try schemeExecutionAction(action: $0, graph: graph, generatedProjects: generatedProjects, rootPath: rootPath)
        }
        
        postActions = try buildAction.postActions.map {
            try schemeExecutionAction(action: $0, graph: graph, generatedProjects: generatedProjects, rootPath: rootPath)
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
    ///   - graph: Tuist graph.
    ///   - rootPath: Root path to either project or workspace.
    ///   - generatedProjects: Project paths mapped to generated projects.
    /// - Returns: Scheme test action.
    func schemeTestAction(scheme: Scheme,
                          graph: Graphing,
                          rootPath: AbsolutePath,
                          generatedProjects: [AbsolutePath: GeneratedProject]) throws -> XCScheme.TestAction? {
        guard let testAction = scheme.testAction else { return nil }
        
        var testables: [XCScheme.TestableReference] = []
        var preActions: [XCScheme.ExecutionAction] = []
        var postActions: [XCScheme.ExecutionAction] = []

        try testAction.targets.forEach { testableTarget in
            guard let reference = try createBuildableReference(targetReference: testableTarget.target,
                                                               graph: graph,
                                                               rootPath: rootPath,
                                                               generatedProjects: generatedProjects) else { return }
            
            let testable = XCScheme.TestableReference(skipped: testableTarget.isSkipped,
                                                      parallelizable: testableTarget.isParallelizable,
                                                      randomExecutionOrdering: testableTarget.isRandomExecutionOrdering,
                                                      buildableReference: reference)
            testables.append(testable)
        }
        
        preActions = try testAction.preActions.map { try schemeExecutionAction(action: $0,
                                                                               graph: graph,
                                                                               generatedProjects: generatedProjects,
                                                                               rootPath: rootPath) }
        postActions = try testAction.postActions.map { try schemeExecutionAction(action: $0,
                                                                                 graph: graph,
                                                                                 generatedProjects: generatedProjects,
                                                                                 rootPath: rootPath) }

        var args: XCScheme.CommandLineArguments?
        var environments: [XCScheme.EnvironmentVariable]?

        if let arguments = testAction.arguments {
            args = XCScheme.CommandLineArguments(arguments: commandlineArgruments(arguments.launch))
            environments = environmentVariables(arguments.environment)
        }
        
        let codeCoverageTargets = try testAction.codeCoverageTargets.compactMap {
            try testCoverageTargetReferences(target: $0,
                                             graph: graph,
                                             generatedProjects: generatedProjects,
                                             rootPath: rootPath)
        }

        let onlyGenerateCoverageForSpecifiedTargets = codeCoverageTargets.count > 0 ? true : nil

        let shouldUseLaunchSchemeArgsEnv: Bool = args == nil && environments == nil

        return XCScheme.TestAction(buildConfiguration: testAction.configurationName,
                                   macroExpansion: nil,
                                   testables: testables,
                                   preActions: preActions,
                                   postActions: postActions,
                                   shouldUseLaunchSchemeArgsEnv: shouldUseLaunchSchemeArgsEnv,
                                   codeCoverageEnabled: testAction.coverage,
                                   codeCoverageTargets: codeCoverageTargets,
                                   onlyGenerateCoverageForSpecifiedTargets: onlyGenerateCoverageForSpecifiedTargets,
                                   commandlineArguments: args,
                                   environmentVariables: environments)
    }
    
    /// Generates the scheme launch action.
    ///
    /// - Parameters:
    ///   - scheme: Scheme manifest.
    ///   - graph: Tuist graph.
    ///   - rootPath: Root path to either project or workspace.
    ///   - generatedProjects: Project paths mapped to generated projects.
    /// - Returns: Scheme launch action.
    func schemeLaunchAction(scheme: Scheme,
                            graph: Graphing,
                            rootPath: AbsolutePath,
                            generatedProjects: [AbsolutePath: GeneratedProject]) throws -> XCScheme.LaunchAction? {
        guard var target = try defaultTargetReference(scheme: scheme) else { return nil }
        
        if let executable = scheme.runAction?.executable {
            target = executable
        }
        
        guard let targetNode = try graph.target(path: target.projectPath, name: target.name) else { return nil }
        guard let buildableReference = try createBuildableReference(targetReference: target,
                                                                    graph: graph,
                                                                    rootPath: rootPath,
                                                                    generatedProjects: generatedProjects) else { return nil }
        
        var buildableProductRunnable: XCScheme.BuildableProductRunnable?
        var macroExpansion: XCScheme.BuildableReference?

        if targetNode.target.product.runnable {
            buildableProductRunnable = XCScheme.BuildableProductRunnable(buildableReference: buildableReference, runnableDebuggingMode: "0")
        } else {
            macroExpansion = buildableReference
        }

        var commandlineArguments: XCScheme.CommandLineArguments?
        var environments: [XCScheme.EnvironmentVariable]?

        if let arguments = scheme.runAction?.arguments {
            commandlineArguments = XCScheme.CommandLineArguments(arguments: commandlineArgruments(arguments.launch))
            environments = environmentVariables(arguments.environment)
        }

        let buildConfiguration = scheme.runAction?.configurationName ?? defaultDebugBuildConfigurationName(in: targetNode.project)
        return XCScheme.LaunchAction(runnable: buildableProductRunnable,
                                     buildConfiguration: buildConfiguration,
                                     macroExpansion: macroExpansion,
                                     commandlineArguments: commandlineArguments,
                                     environmentVariables: environments)
    }
    
    /// Generates the scheme profile action for a given target.
    ///
    /// - Parameters:
    ///   - scheme: Target manifest.
    ///   - graph: Tuist graph.
    ///   - rootPath: Root path to either project or workspace.
    ///   - generatedProjects: Project paths mapped to generated projects.
    /// - Returns: Scheme profile action.
    func schemeProfileAction(scheme: Scheme,
                             graph: Graphing,
                             rootPath: AbsolutePath,
                             generatedProjects: [AbsolutePath: GeneratedProject]) throws -> XCScheme.ProfileAction? {
        
        guard var target = try defaultTargetReference(scheme: scheme) else { return nil }
        if let executable = scheme.runAction?.executable {
            target = executable
        }
        guard let targetNode = try graph.target(path: target.projectPath, name: target.name) else { return nil }
        guard let buildableReference = try createBuildableReference(targetReference: target,
                                                                    graph: graph,
                                                                    rootPath: rootPath,
                                                                    generatedProjects: generatedProjects) else { return nil }
        
        var buildableProductRunnable: XCScheme.BuildableProductRunnable?
        var macroExpansion: XCScheme.BuildableReference?
        
        if targetNode.target.product.runnable {
            buildableProductRunnable = XCScheme.BuildableProductRunnable(buildableReference: buildableReference, runnableDebuggingMode: "0")
        } else {
            macroExpansion = buildableReference
        }
        
        let buildConfiguration = defaultReleaseBuildConfigurationName(in: targetNode.project)
        return XCScheme.ProfileAction(buildableProductRunnable: buildableProductRunnable,
                                      buildConfiguration: buildConfiguration,
                                      macroExpansion: macroExpansion)
    }
    
    /// Returns the scheme analyze action.
    ///
    /// - Parameters:
    ///     - scheme: Scheme manifest.
    ///     - graph: Tuist graph.
    ///     - rootPath: Root path to either project or workspace.
    ///     - generatedProjects: Project paths mapped to generated projects.
    /// - Returns: Scheme analyze action.
    func schemeAnalyzeAction(scheme: Scheme,
                             graph: Graphing,
                             rootPath: AbsolutePath,
                             generatedProjects: [AbsolutePath: GeneratedProject]) throws -> XCScheme.AnalyzeAction? {
        guard let target = try defaultTargetReference(scheme: scheme),
            let targetNode = try graph.target(path: target.projectPath, name: target.name) else { return nil }
        
        let buildConfiguration = defaultDebugBuildConfigurationName(in: targetNode.project)
        return XCScheme.AnalyzeAction(buildConfiguration: buildConfiguration)
    }

    /// Generates the scheme archive action.
    ///
    /// - Parameters:
    ///     - scheme: Scheme manifest.
    ///     - graph: Tuist graph.
    ///     - rootPath: Root path to either project or workspace.
    ///     - generatedProjects: Project paths mapped to generated projects.
    /// - Returns: Scheme archive action.
    func schemeArchiveAction(scheme: Scheme,
                             graph: Graphing,
                             rootPath: AbsolutePath,
                             generatedProjects: [AbsolutePath: GeneratedProject]) throws -> XCScheme.ArchiveAction? {
        
        guard let target = try defaultTargetReference(scheme: scheme),
            let targetNode = try graph.target(path: target.projectPath, name: target.name) else { return nil }

        guard let archiveAction = scheme.archiveAction else {
            return defaultSchemeArchiveAction(for: targetNode.project)
        }
        
        let preActions = try archiveAction.preActions.map {
            try schemeExecutionAction(action: $0, graph: graph, generatedProjects: generatedProjects, rootPath: rootPath)
        }
        
        let postActions = try archiveAction.postActions.map {
            try schemeExecutionAction(action: $0, graph: graph, generatedProjects: generatedProjects, rootPath: rootPath)
        }

        return XCScheme.ArchiveAction(buildConfiguration: archiveAction.configurationName,
                                      revealArchiveInOrganizer: archiveAction.revealArchiveInOrganizer,
                                      customArchiveName: archiveAction.customArchiveName,
                                      preActions: preActions,
                                      postActions: postActions)
    }
    
    func schemeExecutionAction(action: ExecutionAction,
                               graph: Graphing,
                               generatedProjects: [AbsolutePath: GeneratedProject],
                               rootPath: AbsolutePath) throws -> XCScheme.ExecutionAction {

        guard let targetReference = action.target,
            let targetNode = try graph.target(path: targetReference.projectPath, name: targetReference.name),
            let generatedProject = generatedProjects[targetReference.projectPath] else {
                return schemeExecutionAction(action: action)
        }
        return schemeExecutionAction(action: action,
                                     target: targetNode.target,
                                     generatedProject: generatedProject)
    }
    
    private func schemeExecutionAction(action: ExecutionAction) -> XCScheme.ExecutionAction {
        return XCScheme.ExecutionAction(scriptText: action.scriptText,
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
                                       generatedProject: GeneratedProject) -> XCScheme.ExecutionAction {
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
    
    private func resolveRelativeProjectPath(targetNode: TargetNode,
                                            generatedProject: GeneratedProject,
                                            rootPath: AbsolutePath) -> RelativePath {
        let xcodeProjectPath = targetNode.path.appending(component: generatedProject.name)
        return xcodeProjectPath.relative(to: rootPath)
    }
    
    /// Creates a target buildable refernece for a target
    ///
    /// - Parameters:
    ///     - targetReference: The target reference.
    ///     - graph: Tuist graph.
    ///     - rootPath: Path to the project or workspace.
    ///     - generatedProjects: Project paths mapped to generated projects.
    private func createBuildableReference(targetReference: TargetReference,
                                          graph: Graphing,
                                          rootPath: AbsolutePath,
                                          generatedProjects: [AbsolutePath: GeneratedProject]) throws -> XCScheme.BuildableReference? {
        
        let projectPath = targetReference.projectPath
        guard let target = try graph.target(path: projectPath, name: targetReference.name) else { return nil }
        guard let generatedProject = generatedProjects[projectPath] else { return nil }
        guard let pbxTarget = generatedProject.targets[targetReference.name] else { return nil }
        let relativeXcodeProjectPath = resolveRelativeProjectPath(targetNode: target,
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
    private func testCoverageTargetReferences(target: TargetReference,
                                              graph: Graphing,
                                              generatedProjects: [AbsolutePath: GeneratedProject],
                                              rootPath: AbsolutePath) throws -> XCScheme.BuildableReference? {
        return try createBuildableReference(targetReference: target,
                                            graph: graph,
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
        let schemePath: AbsolutePath
        if shared {
            schemePath = path.appending(RelativePath("xcshareddata/xcschemes"))
        } else {
            let username = NSUserName()
            schemePath = path.appending(RelativePath("xcuserdata/\(username).xcuserdatad/xcschemes"))
        }
        if !FileHandler.shared.exists(schemePath) {
            try FileHandler.shared.createFolder(schemePath)
        }
        return schemePath
    }
    
    /// Returns the scheme commandline argument passed on launch
    ///
    /// - Parameters:
    ///     - environments: commandline argument keys.
    /// - Returns: XCScheme.CommandLineArguments.CommandLineArgument.
    private func commandlineArgruments(_ arguments: [String: Bool]) -> [XCScheme.CommandLineArguments.CommandLineArgument] {
        return arguments.map { key, enabled in
            XCScheme.CommandLineArguments.CommandLineArgument(name: key, enabled: enabled)
        }
    }
    
    /// Returns the scheme environment variables
    ///
    /// - Parameters:
    ///     - environments: environment variables
    /// - Returns: XCScheme.EnvironmentVariable.
    private func environmentVariables(_ environments: [String: String]) -> [XCScheme.EnvironmentVariable] {
        return environments.map { key, value in
            XCScheme.EnvironmentVariable(variable: key, value: value, enabled: true)
        }
    }
    
    private func defaultDebugBuildConfigurationName(in project: Project) -> String {
        let debugConfiguration = project.settings.defaultDebugBuildConfiguration()
        let buildConfiguration = debugConfiguration ?? project.settings.configurations.keys.first

        return buildConfiguration?.name ?? BuildConfiguration.debug.name
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
                                          projectPath: String) -> XCScheme.BuildableReference {
        return XCScheme.BuildableReference(referencedContainer: "container:\(projectPath)",
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
    
    private func defaultTargetReference(scheme: Scheme) throws  -> TargetReference? {
        return scheme.buildAction?.targets.first
    }
}
