import Basic
import Foundation
import TuistCore
import XcodeProj

/// Protocol that defines the interface of the schemes generation.
protocol SchemesGenerating {
    /// Generates the schemes for the project targets.
    ///
    /// - Parameters:
    ///   - project: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    /// - Throws: A FatalError if the generation of the schemes fails.
    func generateTargetSchemes(project: Project,
                               generatedProject: GeneratedProject) throws
}

final class SchemesGenerator: SchemesGenerating {
    /// Default last upgrade version for generated schemes.
    private static let defaultLastUpgradeVersion = "1010"

    /// Default version for generated schemes.
    private static let defaultVersion = "1.3"

    /// Instance to interact with the file system.
    let fileHandler: FileHandling

    /// Initializes the schemes generator with its attributes.
    ///
    /// - Parameter fileHandler: File handler.
    init(fileHandler: FileHandling = FileHandler()) {
        self.fileHandler = fileHandler
    }

    /// Generates the schemes for the project manifest.
    ///
    /// - Parameters:
    ///   - project: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    /// - Throws: A FatalError if the generation of the schemes fails.
    func generateTargetSchemes(project: Project, generatedProject: GeneratedProject) throws {

        /// Generate scheme from manifest
        try project.schemes.forEach { scheme in
            try generateScheme(scheme: scheme, project: project, generatedProject: generatedProject)
        }
        
        /// Generate scheme for every targets in Project that is not defined in Manifest
        try project.targets.forEach { target in
            
            if !project.schemes.contains(where: { $0.name == target.name }) {
                
                let scheme = Scheme(name: target.name,
                                    shared: true,
                                    buildAction: BuildAction(targets: [target.name]),
                                    testAction: TestAction(targets: [target.name]),
                                    runAction: RunAction(config: .debug,
                                                         executable: target.name,
                                                         arguments: Arguments(environment: target.environment)))
                
                try generateScheme(scheme: scheme,
                                   project: project,
                                   generatedProject: generatedProject)
            }
        }
    }
    
    /// Generates the scheme.
    ///
    /// - Parameters:
    ///   - scheme: Scheme manifest.
    ///   - project: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    /// - Throws: An error if the generation fails.
    func generateScheme(scheme: Scheme,
                        project: Project,
                        generatedProject: GeneratedProject) throws {
        let schemesDirectory = try createSchemesDirectory(projectPath: generatedProject.path)
        let schemePath = schemesDirectory.appending(component: "\(scheme.name).xcscheme")
        
        let generatedBuildAction = schemeBuildAction(scheme: scheme, project: project, generatedProject: generatedProject)
        let generatedTestAction = schemeTestAction(scheme: scheme, project: project, generatedProject: generatedProject)
        let generatedLaunchAction = schemeLaunchAction(scheme: scheme, project: project, generatedProject: generatedProject)
        let generatedProfileAction = schemeProfileAction(scheme: scheme, project: project, generatedProject: generatedProject)
        
        let scheme = XCScheme(name: scheme.name,
                              lastUpgradeVersion: SchemesGenerator.defaultLastUpgradeVersion,
                              version: SchemesGenerator.defaultVersion,
                              buildAction: generatedBuildAction,
                              testAction: generatedTestAction,
                              launchAction: generatedLaunchAction,
                              profileAction: generatedProfileAction,
                              analyzeAction: schemeAnalyzeAction(),
                              archiveAction: schemeArchiveAction())
        try scheme.write(path: schemePath.path, override: true)
    }


    /// Returns the build action for the project scheme.
    ///
    /// - Parameters:
    ///   - project: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    ///   - graph: Dependencies graph.
    /// - Returns: Scheme build action.
    func projectBuildAction(project: Project,
                            generatedProject: GeneratedProject,
                            graph: Graphing) -> XCScheme.BuildAction {
        let targets = project.sortedTargetsForProjectScheme(graph: graph)
        let entries: [XCScheme.BuildAction.Entry] = targets.map { (target) -> XCScheme.BuildAction.Entry in

            let pbxTarget = generatedProject.targets[target.name]!
            let buildableReference = targetBuildableReference(target: target,
                                                              pbxTarget: pbxTarget,
                                                              projectName: generatedProject.name)
            var buildFor: [XCScheme.BuildAction.Entry.BuildFor] = []
            if target.product.testsBundle {
                buildFor.append(.testing)
            } else {
                buildFor.append(contentsOf: [.analyzing, .archiving, .profiling, .running, .testing])
            }

            return XCScheme.BuildAction.Entry(buildableReference: buildableReference,
                                              buildFor: buildFor)
        }

        return XCScheme.BuildAction(buildActionEntries: entries,
                                    parallelizeBuild: true,
                                    buildImplicitDependencies: true)
    }

    /// Generates the test action for the project scheme.
    ///
    /// - Parameters:
    ///   - project: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    /// - Returns: Scheme test action.
    func projectTestAction(project: Project,
                           generatedProject: GeneratedProject) -> XCScheme.TestAction {
        var testables: [XCScheme.TestableReference] = []
        let testTargets = project.targets.filter { $0.product.testsBundle }

        testTargets.forEach { target in
            let pbxTarget = generatedProject.targets[target.name]!

            let reference = targetBuildableReference(target: target,
                                                     pbxTarget: pbxTarget,
                                                     projectName: generatedProject.name)
            let testable = XCScheme.TestableReference(skipped: false,
                                                      buildableReference: reference)
            testables.append(testable)
        }

        return XCScheme.TestAction(buildConfiguration: "Debug",
                                   macroExpansion: nil,
                                   testables: testables)
    }

    /// Generates the scheme test action.
    ///
    /// - Parameters:
    ///   - scheme: Scheme manifest.
    ///   - project: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    /// - Returns: Scheme test action.
    func schemeTestAction(scheme: Scheme,
                          project: Project,
                          generatedProject: GeneratedProject) -> XCScheme.TestAction? {
        guard let testAction = scheme.testAction else { return nil }
        
        var testables: [XCScheme.TestableReference] = []
        var preActions: [XCScheme.ExecutionAction] = []
        var postActions: [XCScheme.ExecutionAction] = []

        testAction.targets.forEach { name in
            guard let target = project.targets.first(where: { $0.name == name }), target.product.testsBundle else { return }
            guard let pbxTarget = generatedProject.targets[name] else { return }
            
            let reference = self.targetBuildableReference(target: target,
                                                          pbxTarget: pbxTarget,
                                                          projectName: generatedProject.name)
            
            let testable = XCScheme.TestableReference(skipped: false, buildableReference: reference)
            testables.append(testable)
        }
        
        preActions = schemeExecutionActions(actions: testAction.preActions,
                                            project: project,
                                            generatedProject: generatedProject)
        
        postActions = schemeExecutionActions(actions: testAction.postActions,
                                             project: project,
                                             generatedProject: generatedProject)
        
        var args: XCScheme.CommandLineArguments?
        var environments: [XCScheme.EnvironmentVariable]?
        
        if let arguments = testAction.arguments {
            args = XCScheme.CommandLineArguments(arguments: commandlineArgruments(arguments.launch))
            environments = environmentVariables(arguments.environment)
        }

        let shouldUseLaunchSchemeArgsEnv: Bool = args == nil && environments == nil
        
        return XCScheme.TestAction(buildConfiguration: "Debug",
                                   macroExpansion: nil,
                                   testables: testables,
                                   preActions: preActions,
                                   postActions: postActions,
                                   shouldUseLaunchSchemeArgsEnv: shouldUseLaunchSchemeArgsEnv,
                                   codeCoverageEnabled: testAction.coverage,
                                   commandlineArguments: args,
                                   environmentVariables: environments)
    }

    /// Generates the scheme build action.
    ///
    /// - Parameters:
    ///   - scheme: Scheme manifest.
    ///   - project: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    /// - Returns: Scheme build action.
    func schemeBuildAction(scheme: Scheme,
                           project: Project,
                           generatedProject: GeneratedProject) -> XCScheme.BuildAction? {
        guard let buildAction = scheme.buildAction else { return nil }
        
        let buildFor: [XCScheme.BuildAction.Entry.BuildFor] = [
            .analyzing, .archiving, .profiling, .running, .testing,
        ]

        var entries: [XCScheme.BuildAction.Entry] = []
        var preActions: [XCScheme.ExecutionAction] = []
        var postActions: [XCScheme.ExecutionAction] = []

        buildAction.targets.forEach { name in
            guard let target = project.targets.first(where: { $0.name == name }) else { return }
            guard let pbxTarget = generatedProject.targets[name] else { return }
            let buildableReference = self.targetBuildableReference(target: target,
                                                                   pbxTarget: pbxTarget,
                                                                   projectName: generatedProject.name)
            
            entries.append(XCScheme.BuildAction.Entry(buildableReference: buildableReference, buildFor: buildFor))
        }

        preActions = schemeExecutionActions(actions: buildAction.preActions,
                                            project: project,
                                            generatedProject: generatedProject)
        
        postActions = schemeExecutionActions(actions: buildAction.postActions,
                                             project: project,
                                             generatedProject: generatedProject)
        
        return XCScheme.BuildAction(buildActionEntries: entries,
                                    preActions: preActions,
                                    postActions: postActions,
                                    parallelizeBuild: true,
                                    buildImplicitDependencies: true)
    }

    /// Generates the scheme launch action.
    ///
    /// - Parameters:
    ///   - scheme: Scheme manifest.
    ///   - project: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    /// - Returns: Scheme launch action.
    func schemeLaunchAction(scheme: Scheme,
                            project: Project,
                            generatedProject: GeneratedProject) -> XCScheme.LaunchAction? {
        
        guard var target = project.targets.first(where: { $0.name == scheme.buildAction?.targets.first }) else { return nil }
        
        if let executable = scheme.runAction?.executable {
            guard let runableTarget = project.targets.first(where: { $0.name == executable }) else { return nil }
            target = runableTarget
        }
        
        guard let pbxTarget = generatedProject.targets[target.name] else { return nil }

        var buildableProductRunnable: XCScheme.BuildableProductRunnable?
        var macroExpansion: XCScheme.BuildableReference?
        let buildableReference = targetBuildableReference(target: target, pbxTarget: pbxTarget, projectName: generatedProject.name)
        if target.product.runnable {
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
        
        return XCScheme.LaunchAction(buildableProductRunnable: buildableProductRunnable,
                                     buildConfiguration: "Debug",
                                     macroExpansion: macroExpansion,
                                     commandlineArguments: commandlineArguments,
                                     environmentVariables: environments)
    }

    /// Generates the scheme profile action for a given target.
    ///
    /// - Parameters:
    ///   - target: Target manifest.
    ///   - pbxTarget: Xcode native target.
    ///   - projectName: Project name with .xcodeproj extension.
    /// - Returns: Scheme profile action.
    func schemeProfileAction(scheme: Scheme,
                             project: Project,
                             generatedProject: GeneratedProject) -> XCScheme.ProfileAction? {
        
        guard var target = project.targets.first(where: { $0.name == scheme.buildAction?.targets.first }) else { return nil }
        
        if let executable = scheme.runAction?.executable {
            guard let runableTarget = project.targets.first(where: { $0.name == executable }) else { return nil }
            target = runableTarget
        }
        
        guard let pbxTarget = generatedProject.targets[target.name] else { return nil }

        var buildableProductRunnable: XCScheme.BuildableProductRunnable?
        var macroExpansion: XCScheme.BuildableReference?
        let buildableReference = targetBuildableReference(target: target, pbxTarget: pbxTarget, projectName: generatedProject.name)

        if target.product.runnable {
            buildableProductRunnable = XCScheme.BuildableProductRunnable(buildableReference: buildableReference, runnableDebuggingMode: "0")
        } else {
            macroExpansion = buildableReference
        }
        return XCScheme.ProfileAction(buildableProductRunnable: buildableProductRunnable,
                                      buildConfiguration: "Release",
                                      macroExpansion: macroExpansion)
    }
    
    /// Returns the scheme pre/post actions.
    ///
    /// - Parameters:
    ///   - actions: pre/post action manifest.
    ///   - project: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    /// - Returns: Scheme actions.
    func schemeExecutionActions(actions: [ExecutionAction],
                                project: Project,
                                generatedProject: GeneratedProject) -> [XCScheme.ExecutionAction] {
        
        /// Return Buildable Reference for Scheme Action
        func schemeBuildableReference(targetName: String?, project: Project, generatedProject: GeneratedProject) -> XCScheme.BuildableReference? {
            
            guard let targetName = targetName else { return nil }
            guard let target = project.targets.first(where: { $0.name == targetName }) else { return nil }
            guard let pbxTarget = generatedProject.targets[targetName] else { return nil }
            
            return self.targetBuildableReference(target: target, pbxTarget: pbxTarget, projectName: generatedProject.name)
        }
        
        var schemeActions: [XCScheme.ExecutionAction] = []
        actions.forEach { action in
            let schemeAction = XCScheme.ExecutionAction(scriptText: action.scriptText,
                                                        title: action.title,
                                                        environmentBuildable: nil)
            
            schemeAction.environmentBuildable = schemeBuildableReference(targetName: action.target,
                                                                         project: project,
                                                                         generatedProject: generatedProject)
            schemeActions.append(schemeAction)
        }
        return schemeActions
    }

    /// Returns the scheme commandline argument passed on launch
    ///
    /// - Parameters:
    /// - environments: commandline argument keys.
    /// - Returns: XCScheme.CommandLineArguments.CommandLineArgument.
    func commandlineArgruments(_ arguments: [String: Bool]) -> [XCScheme.CommandLineArguments.CommandLineArgument] {
        return arguments.map { (key, enabled) in
            XCScheme.CommandLineArguments.CommandLineArgument(name: key, enabled: enabled)
        }
    }
    
    /// Returns the scheme environment variables
    ///
    /// - Parameters:
    /// - environments: environment variables
    /// - Returns: XCScheme.EnvironmentVariable.
    func environmentVariables(_ environments: [String: String]) -> [XCScheme.EnvironmentVariable] {
        return environments.map { (key, value) in
            XCScheme.EnvironmentVariable(variable: key, value: value, enabled: true)
        }
    }
    
    /// Returns the scheme buildable reference for a given target.
    ///
    /// - Parameters:
    ///   - target: Target manifest.
    ///   - pbxTarget: Xcode native target.
    ///   - projectName: Project name with the .xcodeproj extension.
    /// - Returns: Buildable reference.
    func targetBuildableReference(target: Target, pbxTarget: PBXNativeTarget, projectName: String) -> XCScheme.BuildableReference {
        return XCScheme.BuildableReference(referencedContainer: "container:\(projectName)",
                                           blueprint: pbxTarget,
                                           buildableName: target.productNameWithExtension,
                                           blueprintName: target.name,
                                           buildableIdentifier: "primary")
    }

    /// Returns the scheme analyze action
    ///
    /// - Returns: Scheme analyze action.
    func schemeAnalyzeAction() -> XCScheme.AnalyzeAction {
        return XCScheme.AnalyzeAction(buildConfiguration: "Debug")
    }

    /// Returns the scheme archive action
    ///
    /// - Returns: Scheme archive action.
    func schemeArchiveAction() -> XCScheme.ArchiveAction {
        return XCScheme.ArchiveAction(buildConfiguration: "Release",
                                      revealArchiveInOrganizer: true)
    }

    /// Creates the directory where the schemes are stored inside the project.
    /// If the directory exists it does not re-create it.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the Xcode project.
    /// - Returns: Path to the schemes directory.
    /// - Throws: A FatalError if the creation of the directory fails.
    private func createSchemesDirectory(projectPath: AbsolutePath) throws -> AbsolutePath {
        let path = projectPath.appending(RelativePath("xcshareddata/xcschemes"))
        if !fileHandler.exists(path) {
            try fileHandler.createFolder(path)
        }
        return path
    }
}
