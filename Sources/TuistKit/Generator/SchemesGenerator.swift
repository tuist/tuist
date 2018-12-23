import Basic
import Foundation
import xcodeproj
import TuistCore

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
    
    /// Instance to interact with the file system.
    let fileHandler: FileHandling
    
    /// Initializes the schemes generator with its attributes.
    ///
    /// - Parameter fileHandler: File handler.
    init(fileHandler: FileHandling = FileHandler()) {
        self.fileHandler = fileHandler
    }
    
    /// Generates the schemes for the project targets.
    ///
    /// - Parameters:
    ///   - project: Project manifest.
    ///   - generatedProject: Generated Xcode project.
    /// - Throws: A FatalError if the generation of the schemes fails.
    func generateTargetSchemes(project: Project,
                               generatedProject: GeneratedProject) throws {
        try project.targets.forEach { (target) in
            let pbxTarget = generatedProject.targets[target.name]!
            try generateTargetScheme(target: target,
                                     pbxTarget: pbxTarget,
                                     projectPath: generatedProject.path)
        }
    }
    
    /// Generates the scheme for a given target.
    ///
    /// - Parameters:
    ///   - target: Target manifest.
    ///   - pbxTarget: Xcode native target.
    ///   - projectPath: Path to the Xcode project (folder with extension .xcodeproj)
    /// - Throws: An error if the generation fails.
    func generateTargetScheme(target: Target,
                              pbxTarget: PBXNativeTarget,
                              projectPath: AbsolutePath) throws {
        let schemesDirectory = try createSchemesDirectory(projectPath: projectPath)
        let schemePath = schemesDirectory.appending(component: "\(target.name).xcscheme")
        var buildAction: XCScheme.BuildAction?
        var testAction: XCScheme.TestAction?
        
        let scheme = XCScheme(name: target.name,
                              lastUpgradeVersion: "1010",
                              version: "1.3",
                              buildAction: buildAction,
                              testAction: testAction,
                              launchAction: launchAction(target: target,
                                                         pbxTarget: pbxTarget,
                                                         projectPath: projectPath),
                              profileAction: profileAction(target: target,
                                                           pbxTarget: pbxTarget,
                                                           projectPath: projectPath),
                              analyzeAction: analyzeAction(),
                              archiveAction: archiveAction())
        try scheme.write(path: schemePath.path, override: true)
    }
    
    /// Generates the scheme launch action for a given target.
    ///
    /// - Parameters:
    ///   - target: Target manifest.
    ///   - pbxTarget: Xcode native target.
    ///   - projectPath: Path to the Xcode project.
    /// - Returns: Scheme launch action.
    func launchAction(target: Target,
                       pbxTarget: PBXNativeTarget,
                       projectPath: AbsolutePath) -> XCScheme.LaunchAction? {
        var buildableProductRunnable: XCScheme.BuildableProductRunnable?
        var macroExpansion: XCScheme.BuildableReference?
        let buildableReference = self.buildableReference(target: target, pbxTarget: pbxTarget, projectPath: projectPath)
        if target.product.runnable {
            buildableProductRunnable = XCScheme.BuildableProductRunnable(buildableReference: buildableReference, runnableDebuggingMode: "0")
        } else {
            macroExpansion = buildableReference
        }
        return XCScheme.LaunchAction(buildableProductRunnable: buildableProductRunnable,
                                     buildConfiguration: "Debug",
                                     macroExpansion: macroExpansion)
    }
    
    /// Generates the scheme profile action for a given target.
    ///
    /// - Parameters:
    ///   - target: Target manifest.
    ///   - pbxTarget: Xcode native target.
    ///   - projectPath: Path to the Xcode project.
    /// - Returns: Scheme profile action.
    func profileAction(target: Target,
                       pbxTarget: PBXNativeTarget,
                       projectPath: AbsolutePath) -> XCScheme.ProfileAction? {
        var buildableProductRunnable: XCScheme.BuildableProductRunnable?
        var macroExpansion: XCScheme.BuildableReference?
        let buildableReference = self.buildableReference(target: target, pbxTarget: pbxTarget, projectPath: projectPath)
        
        if target.product.runnable {
            buildableProductRunnable = XCScheme.BuildableProductRunnable(buildableReference: buildableReference, runnableDebuggingMode: "0")
        } else {
            macroExpansion = buildableReference
        }
        return XCScheme.ProfileAction(buildableProductRunnable: buildableProductRunnable,
                                      buildConfiguration: "Release",
                                      macroExpansion: macroExpansion)
    }
    
    /// Returns the scheme buildable reference for a given target.
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
    
    /// Returns the scheme analyze action for a given target.
    ///
    /// - Returns: Scheme analyze action.
    func analyzeAction() -> XCScheme.AnalyzeAction {
        return XCScheme.AnalyzeAction(buildConfiguration: "Debug")
    }
    
    /// Returns the scheme archive action for a given target.
    ///
    /// - Returns: Scheme archive action.
    func archiveAction() -> XCScheme.ArchiveAction {
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
    fileprivate func createSchemesDirectory(projectPath: AbsolutePath) throws -> AbsolutePath {
        let path = projectPath.appending(RelativePath("xcshareddata/xcschemes"))
        if !fileHandler.exists(path) {
            try self.fileHandler.createFolder(path)
        }
        return path
    }
    
}
