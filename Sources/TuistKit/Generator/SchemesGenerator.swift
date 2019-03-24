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
                                     projectName: generatedProject.name,
                                     projectPath: generatedProject.path)
        }
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

    /// Generates the scheme for a given target.
    ///
    /// - Parameters:
    ///   - target: Target manifest.
    ///   - pbxTarget: Xcode native target.
    ///   - projectName: Project name with the .xcodeproj extension.
    ///   - projectPath: Path to the Xcodeproj project.
    /// - Throws: An error if the generation fails.
    func generateTargetScheme(target: Target,
                              pbxTarget: PBXNativeTarget,
                              projectName: String,
                              projectPath: AbsolutePath) throws {
        let schemesDirectory = try createSchemesDirectory(projectPath: projectPath)
        let schemePath = schemesDirectory.appending(component: "\(target.name).xcscheme")

        let scheme = XCScheme(name: target.name,
                              lastUpgradeVersion: SchemesGenerator.defaultLastUpgradeVersion,
                              version: SchemesGenerator.defaultVersion,
                              buildAction: targetBuildAction(target: target,
                                                             pbxTarget: pbxTarget,
                                                             projectName: projectName),
                              testAction: targetTestAction(target: target,
                                                           pbxTarget: pbxTarget,
                                                           projectName: projectName),
                              launchAction: targetLaunchAction(target: target,
                                                               pbxTarget: pbxTarget,
                                                               projectName: projectName),
                              profileAction: targetProfileAction(target: target,
                                                                 pbxTarget: pbxTarget,
                                                                 projectName: projectName),
                              analyzeAction: targetAnalyzeAction(),
                              archiveAction: targetArchiveAction())
        try scheme.write(path: schemePath.path, override: true)
    }

    /// Generates the scheme test action for a given target.
    ///
    /// - Parameters:
    ///   - target: Target manifest.
    ///   - pbxTarget: Xcode native target.
    ///   - projectName: Project name with .xcodeproj extension.
    /// - Returns: Scheme test action.
    func targetTestAction(target: Target,
                          pbxTarget: PBXNativeTarget,
                          projectName: String) -> XCScheme.TestAction? {
        var testables: [XCScheme.TestableReference] = []
        if target.product.testsBundle {
            let reference = targetBuildableReference(target: target,
                                                     pbxTarget: pbxTarget,
                                                     projectName: projectName)
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
    ///   - projectName: Project name with the .xcodeproj extension.
    /// - Returns: Scheme build action.
    func targetBuildAction(target: Target,
                           pbxTarget: PBXNativeTarget,
                           projectName: String) -> XCScheme.BuildAction? {
        let buildFor: [XCScheme.BuildAction.Entry.BuildFor] = [
            .analyzing, .archiving, .profiling, .running, .testing,
        ]

        let buildableReference = targetBuildableReference(target: target,
                                                          pbxTarget: pbxTarget,
                                                          projectName: projectName)
        var entries: [XCScheme.BuildAction.Entry] = []
        entries.append(XCScheme.BuildAction.Entry(buildableReference: buildableReference, buildFor: buildFor))

        return XCScheme.BuildAction(buildActionEntries: entries,
                                    parallelizeBuild: true,
                                    buildImplicitDependencies: true)
    }

    /// Generates the scheme launch action for a given target.
    ///
    /// - Parameters:
    ///   - target: Target manifest.
    ///   - pbxTarget: Xcode native target.
    ///   - projectName: Project name with .xcodeproj extension.
    /// - Returns: Scheme launch action.
    func targetLaunchAction(target: Target,
                            pbxTarget: PBXNativeTarget,
                            projectName: String) -> XCScheme.LaunchAction? {
        var buildableProductRunnable: XCScheme.BuildableProductRunnable?
        var macroExpansion: XCScheme.BuildableReference?
        let buildableReference = targetBuildableReference(target: target, pbxTarget: pbxTarget, projectName: projectName)
        if target.product.runnable {
            buildableProductRunnable = XCScheme.BuildableProductRunnable(buildableReference: buildableReference, runnableDebuggingMode: "0")
        } else {
            macroExpansion = buildableReference
        }
        let environmentVariables: [XCScheme.EnvironmentVariable] = target.environment.map { variable, value in
            XCScheme.EnvironmentVariable(variable: variable, value: value, enabled: true)
        }
        return XCScheme.LaunchAction(buildableProductRunnable: buildableProductRunnable,
                                     buildConfiguration: "Debug",
                                     macroExpansion: macroExpansion,
                                     environmentVariables: environmentVariables)
    }

    /// Generates the scheme profile action for a given target.
    ///
    /// - Parameters:
    ///   - target: Target manifest.
    ///   - pbxTarget: Xcode native target.
    ///   - projectName: Project name with .xcodeproj extension.
    /// - Returns: Scheme profile action.
    func targetProfileAction(target: Target,
                             pbxTarget: PBXNativeTarget,
                             projectName: String) -> XCScheme.ProfileAction? {
        var buildableProductRunnable: XCScheme.BuildableProductRunnable?
        var macroExpansion: XCScheme.BuildableReference?
        let buildableReference = targetBuildableReference(target: target, pbxTarget: pbxTarget, projectName: projectName)

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
    ///   - projectName: Project name with the .xcodeproj extension.
    /// - Returns: Buildable reference.
    func targetBuildableReference(target: Target, pbxTarget: PBXNativeTarget, projectName: String) -> XCScheme.BuildableReference {
        return XCScheme.BuildableReference(referencedContainer: "container:\(projectName)",
                                           blueprint: pbxTarget,
                                           buildableName: target.productName,
                                           blueprintName: target.name,
                                           buildableIdentifier: "primary")
    }

    /// Returns the scheme analyze action for a given target.
    ///
    /// - Returns: Scheme analyze action.
    func targetAnalyzeAction() -> XCScheme.AnalyzeAction {
        return XCScheme.AnalyzeAction(buildConfiguration: "Debug")
    }

    /// Returns the scheme archive action for a given target.
    ///
    /// - Returns: Scheme archive action.
    func targetArchiveAction() -> XCScheme.ArchiveAction {
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
