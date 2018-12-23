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
        try project.targets.forEach { target in
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

        let scheme = XCScheme(name: target.name,
                              lastUpgradeVersion: "1010",
                              version: "1.3",
                              buildAction: buildAction(target: target,
                                                       pbxTarget: pbxTarget,
                                                       projectPath: projectPath),
                              testAction: testAction(target: target,
                                                     pbxTarget: pbxTarget,
                                                     projectPath: projectPath),
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

    /// Generates the scheme test action for a given target.
    ///
    /// - Parameters:
    ///   - target: Target manifest.
    ///   - pbxTarget: Xcode native target.
    ///   - projectPath: Path to the Xcode project.
    /// - Returns: Scheme test action.
    func testAction(target: Target,
                    pbxTarget: PBXNativeTarget,
                    projectPath: AbsolutePath) -> XCScheme.TestAction? {
        var testables: [XCScheme.TestableReference] = []
        if target.product.testsBundle {
            let reference = buildableReference(target: target,
                                               pbxTarget: pbxTarget,
                                               projectPath: projectPath)
            let testable = XCScheme.TestableReference(skipped: false,
                                                      buildableReference: reference)
            testables.append(testable)
        }
        return XCScheme.TestAction(buildConfiguration: "Debug",
                                   macroExpansion: nil,
                                   testables: testables)
    }

    /// Generates the scheme build action for a given target.
    ///
    /// - Parameters:
    ///   - target: Target manifest.
    ///   - pbxTarget: Xcode native target.
    ///   - projectPath: Path to the Xcode project.
    /// - Returns: Scheme build action.
    func buildAction(target: Target,
                     pbxTarget: PBXNativeTarget,
                     projectPath: AbsolutePath) -> XCScheme.BuildAction? {
        let buildFor: [XCScheme.BuildAction.Entry.BuildFor] = [
            .analyzing, .archiving, .profiling, .running, .testing,
        ]

        let buildableReference = self.buildableReference(target: target,
                                                         pbxTarget: pbxTarget,
                                                         projectPath: projectPath)
        var entries: [XCScheme.BuildAction.Entry] = []

        // If the target is a tests bundle, Xcode infers that the target needs to be built.
        if !target.product.testsBundle {
            entries.append(XCScheme.BuildAction.Entry(buildableReference: buildableReference, buildFor: buildFor))
        }

        return XCScheme.BuildAction(buildActionEntries: entries,
                                    parallelizeBuild: true,
                                    buildImplicitDependencies: true)
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
            try fileHandler.createFolder(path)
        }
        return path
    }
}
