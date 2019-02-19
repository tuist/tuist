import Basic
import Foundation
import TuistCore
import xcodeproj

/// Protocol that defines the interface of the schemes generation.
protocol SchemesGenerating {
    /// Generates the schemes for the project targets.
    ///
    /// - Parameters:
    ///   - project: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    /// - Throws: A FatalError if the generation of the schemes fails.
    func generateSchemes(project: Project,
                         generatedProject: GeneratedProject) throws
}

final class SchemesGenerator: SchemesGenerating {
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
    func generateSchemes(project: Project, generatedProject: GeneratedProject) throws {
        
        if project.schemes.isEmpty {
            /// Generate scheme for every targets in Project
            try generateTargetSchemes(project: project, generatedProject: generatedProject)
        } else {
            /// Generate scheme from  manifest
            try project.schemes.forEach { scheme in
                try generateScheme(scheme: scheme, project: project, generatedProject: generatedProject)
            }
        }
    }
    
    /// Generates the schemes for the project targets.
    ///
    /// - Parameters:
    ///   - project: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    /// - Throws: A FatalError if the generation of the schemes fails.

    func generateTargetSchemes(project: Project, generatedProject: GeneratedProject) throws {
        try project.targets.forEach { target in
            let scheme = Scheme(name: target.name,
                                shared: true,
                                buildAction: BuildAction(targets: [target.name]),
                                testAction: TestAction(targets: [target.name]),
                                runAction: RunAction(config: .debug, executable: target.name))
            
            try generateScheme(scheme: scheme,
                               project: project,
                               generatedProject: generatedProject)
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

        let generatedBuildAction = buildAction(scheme: scheme, project: project, generatedProject: generatedProject)
        let generatedTestAction = testAction(scheme: scheme, project: project, generatedProject: generatedProject)
        let generatedLaunchAction = launchAction(scheme: scheme, project: project, generatedProject: generatedProject)
        let generatedProfileAction = profileAction(scheme: scheme, project: project, generatedProject: generatedProject)
        let generatedArchiveAction = archiveAction(scheme: scheme, project: project, generatedProject: generatedProject)

        let scheme = XCScheme(name: scheme.name,
                              lastUpgradeVersion: "1010",
                              version: "1.7",
                              buildAction: generatedBuildAction,
                              testAction: generatedTestAction,
                              launchAction: generatedLaunchAction,
                              profileAction: generatedProfileAction,
                              analyzeAction: analyzeAction(),
                              archiveAction: generatedArchiveAction)
        try scheme.write(path: schemePath.path, override: true)
    }

    /// Generates the scheme test action.
    ///
    /// - Parameters:
    ///   - scheme: Scheme manifest.
    ///   - project: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    /// - Returns: Scheme test action.
    func testAction(scheme: Scheme,
                    project: Project,
                    generatedProject: GeneratedProject) -> XCScheme.TestAction? {
        
        var testables: [XCScheme.TestableReference] = []
        var preActions: [XCScheme.ExecutionAction] = []
        var postActions: [XCScheme.ExecutionAction] = []
        
        scheme.testAction?.targets.forEach { name in
            guard let target = project.targets.first(where: { $0.name == name }), target.product.testsBundle else { return }
            guard let pbxTarget = generatedProject.targets[name] else { return }
            
            let reference = self.buildableReference(target: target,
                                                    pbxTarget: pbxTarget,
                                                    projectPath: generatedProject.path)
            
            let testable = XCScheme.TestableReference(skipped: false, buildableReference: reference)
            testables.append(testable)
        }
        
        scheme.testAction.flatMap { testAction in
            preActions = schemeActions(actions: testAction.preActions,
                                       project: project,
                                       generatedProject: generatedProject)
            
            postActions = schemeActions(actions: testAction.postActions,
                                        project: project,
                                        generatedProject: generatedProject)
        }
        
        return XCScheme.TestAction(buildConfiguration: "Debug",
                                   macroExpansion: nil,
                                   testables: testables,
                                   preActions: preActions,
                                   postActions: postActions)
    }
    
    /// Generates the scheme build action.
    ///
    /// - Parameters:
    ///   - scheme: Scheme manifest.
    ///   - project: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    /// - Returns: Scheme build action.
    func buildAction(scheme: Scheme,
                     project: Project,
                     generatedProject: GeneratedProject) -> XCScheme.BuildAction? {
        
        let buildFor: [XCScheme.BuildAction.Entry.BuildFor] = [
            .analyzing, .archiving, .profiling, .running, .testing
        ]

        var entries: [XCScheme.BuildAction.Entry] = []
        var preActions: [XCScheme.ExecutionAction] = []
        var postActions: [XCScheme.ExecutionAction] = []

        scheme.buildAction?.targets.forEach { name in
            guard let target = project.targets.first(where: { $0.name == name }) else { return }
            guard let pbxTarget = generatedProject.targets[name] else { return }
            let buildableReference = self.buildableReference(target: target,
                                                             pbxTarget: pbxTarget,
                                                             projectPath: generatedProject.path)
            
            entries.append(XCScheme.BuildAction.Entry(buildableReference: buildableReference, buildFor: buildFor))
        }

        scheme.buildAction.flatMap { buildAction in
            preActions = schemeActions(actions: buildAction.preActions,
                                       project: project,
                                       generatedProject: generatedProject)
            
            postActions = schemeActions(actions: buildAction.postActions,
                                        project: project,
                                        generatedProject: generatedProject)
        }

        return XCScheme.BuildAction(buildActionEntries: entries,
                                    preActions: preActions,
                                    postActions: postActions,
                                    parallelizeBuild: true, buildImplicitDependencies: true)
    }
    
    /// Generates the scheme launch action.
    ///
    /// - Parameters:
    ///   - scheme: Scheme manifest.
    ///   - project: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    /// - Returns: Scheme launch action.
    func launchAction(scheme: Scheme,
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

        let buildableReference = self.buildableReference(target: target, pbxTarget: pbxTarget, projectPath: project.path)
        if target.product.runnable {
            buildableProductRunnable = XCScheme.BuildableProductRunnable(buildableReference: buildableReference, runnableDebuggingMode: "0")
        } else {
            macroExpansion = buildableReference
        }
        let environmentVariables: [XCScheme.EnvironmentVariable] = target.environment.map({ variable, value in
            XCScheme.EnvironmentVariable(variable: variable, value: value, enabled: true)
        })
        
        return XCScheme.LaunchAction(buildableProductRunnable: buildableProductRunnable,
                                     buildConfiguration: "Debug",
                                     macroExpansion: macroExpansion,
                                     environmentVariables: environmentVariables)
    }

    /// Generates the scheme profile action.
    ///
    /// - Parameters:
    ///   - scheme: Scheme manifest.
    ///   - project: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    /// - Returns: Scheme profile action.
    func profileAction(scheme: Scheme,
                       project: Project,
                       generatedProject: GeneratedProject) -> XCScheme.ProfileAction? {
        var buildableProductRunnable: XCScheme.BuildableProductRunnable?
        var macroExpansion: XCScheme.BuildableReference?
        
        guard var target = project.targets.first(where: { $0.name == scheme.buildAction?.targets.first }) else { return nil }
        
        if let executable = scheme.runAction?.executable {
            guard let runableTarget = project.targets.first(where: { $0.name == executable }) else { return nil }
            target = runableTarget
        }
        
        guard let pbxTarget = generatedProject.targets[target.name] else { return nil }

        let buildableReference = self.buildableReference(target: target, pbxTarget: pbxTarget, projectPath: project.path)

        if target.product.runnable {
            buildableProductRunnable = XCScheme.BuildableProductRunnable(buildableReference: buildableReference, runnableDebuggingMode: "0")
        } else {
            macroExpansion = buildableReference
        }
        return XCScheme.ProfileAction(buildableProductRunnable: buildableProductRunnable,
                                      buildConfiguration: "Release",
                                      macroExpansion: macroExpansion)
    }

    ///
    /// - Parameters:
    ///   - target: Target manifest.
    ///   - pbxTarget: Xcode native target.
    ///   - projectPath: Path to the Xcode project.
    /// - Returns: Buildable reference.
    func buildableReference(target: Target, pbxTarget: PBXNativeTarget, projectPath: AbsolutePath) -> XCScheme.BuildableReference {
        let projectName = projectPath.components.last!
        return XCScheme.BuildableReference(referencedContainer: "container:\(projectName)",
                                           blueprint: pbxTarget,
                                           buildableName: target.productName,
                                           blueprintName: target.name,
                                           buildableIdentifier: "primary")
    }
    
    /// Returns the scheme pre/post actions.
    ///
    /// - Parameters:
    ///   - actions: pre/post action manifest.
    ///   - project: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    /// - Returns: Scheme actions.
    func schemeActions(actions: [ExecutionAction],
                       project: Project,
                       generatedProject: GeneratedProject) -> [XCScheme.ExecutionAction] {
        
        /// Return Buildable Reference for Scheme Action
        func schemeBuildableReference(targetName: String?, project: Project, generatedProject: GeneratedProject) -> XCScheme.BuildableReference? {
            
            guard let targetName = targetName else { return nil }
            guard let target = project.targets.first(where: { $0.name == targetName }) else { return nil }
            guard let pbxTarget = generatedProject.targets[targetName] else { return nil }
            
            return self.buildableReference(target: target, pbxTarget: pbxTarget, projectPath: generatedProject.path)
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
    
    /// Returns the scheme analyze action for a given target.
    ///
    /// - Returns: Scheme analyze action.
    func analyzeAction() -> XCScheme.AnalyzeAction {
        return XCScheme.AnalyzeAction(buildConfiguration: "Debug")
    }

    /// Returns the scheme archive action for a given target.
    ///
    /// - Parameters:
    ///   - scheme: Scheme manifest.
    ///   - project: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    /// - Returns: Scheme archive action.
    func archiveAction(scheme: Scheme,
                       project: Project,
                       generatedProject: GeneratedProject) -> XCScheme.ArchiveAction {
        
        var preActions: [XCScheme.ExecutionAction] = []
        var postActions: [XCScheme.ExecutionAction] = []

        scheme.archiveAction.flatMap { action in
            preActions = schemeActions(actions: action.preActions,
                                       project: project,
                                       generatedProject: generatedProject)
            
            postActions = schemeActions(actions: action.postActions,
                                        project: project,
                                        generatedProject: generatedProject)
        }

        return XCScheme.ArchiveAction(buildConfiguration: "Release",
                                      revealArchiveInOrganizer: true,
                                      preActions: preActions,
                                      postActions: postActions)
    }

    /// Creates the directory where the schemes are stored inside the project.
    /// If the directory exists it does not re-create it.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the Xcode project.
    /// - Returns: Path to the schemes directory.
    /// - Throws: A FatalError if the creation of the directory fails.
    fileprivate func createSchemesDirectory(projectPath: AbsolutePath) throws -> AbsolutePath {
        let path = projectPath.appending(RelativePath("xcshareddata/xcschemes"))
        if !fileHandler.exists(path) {
            try fileHandler.createFolder(path)
        }
        return path
    }
}
