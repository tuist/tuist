import Basic
import Foundation
import TuistCore
import xcodeproj

protocol ProjectGenerating: AnyObject {
    func generate(project: Project,
                  options: GenerationOptions,
                  graph: Graphing,
                  sourceRootPath: AbsolutePath?) throws -> GeneratedProject
}

final class ProjectGenerator: ProjectGenerating {
    // MARK: - Attributes

    /// Generator for the project targets.
    let targetGenerator: TargetGenerating

    /// Generator for the project configuration.
    let configGenerator: ConfigGenerating

    /// Generator for the project schemes.
    let schemesGenerator: SchemesGenerating

    /// Printer instance to output messages to the user.
    let printer: Printing

    /// System instance to run commands in the system.
    let system: Systeming

    /// File handler instance to interact with the system files.
    let fileHandler: FileHandling

    // MARK: - Init

    /// Initializes the project generator with its attributes.
    ///
    /// - Parameters:
    ///   - targetGenerator: Generator for the project targets.
    ///   - configGenerator: Generator for the project configuration.
    ///   - schemesGenerator: Generator for the project schemes.
    ///   - printer: Printer instance to output messages to the user.
    ///   - system: System instance to run commands in the system.
    ///   - fileHandler: File handler instance to interact with the system files.
    init(targetGenerator: TargetGenerating = TargetGenerator(),
         configGenerator: ConfigGenerating = ConfigGenerator(),
         schemesGenerator: SchemesGenerating = SchemesGenerator(),
         printer: Printing = Printer(),
         system: Systeming = System(),
         fileHandler: FileHandling = FileHandler()) {
        self.targetGenerator = targetGenerator
        self.configGenerator = configGenerator
        self.schemesGenerator = schemesGenerator
        self.printer = printer
        self.system = system
        self.fileHandler = fileHandler
    }

    // MARK: - ProjectGenerating

    func generate(project: Project,
                  options: GenerationOptions,
                  graph: Graphing,
                  sourceRootPath: AbsolutePath? = nil) throws -> GeneratedProject {
        printer.print("Generating project \(project.name)")

        // Getting the path.
        var sourceRootPath: AbsolutePath! = sourceRootPath
        if sourceRootPath == nil {
            sourceRootPath = project.path
        }
        let xcodeprojPath = sourceRootPath.appending(component: "\(project.name).xcodeproj")

        // Project and workspace.
        let workspaceData = XCWorkspaceData(children: [])
        let workspace = XCWorkspace(data: workspaceData)
        let pbxproj = PBXProj(objectVersion: Xcode.Default.objectVersion,
                              archiveVersion: Xcode.LastKnown.archiveVersion,
                              classes: [:])
        let groups = ProjectGroups.generate(project: project, pbxproj: pbxproj, sourceRootPath: sourceRootPath)
        let fileElements = ProjectFileElements()
        try fileElements.generateProjectFiles(project: project,
                                              graph: graph,
                                              groups: groups,
                                              pbxproj: pbxproj,
                                              sourceRootPath: sourceRootPath)

        let configurationList = try configGenerator.generateProjectConfig(project: project,
                                                                          pbxproj: pbxproj,
                                                                          fileElements: fileElements,
                                                                          options: options)

        let pbxProject = try generatePbxproject(project: project,
                                                configurationList: configurationList,
                                                groups: groups,
                                                pbxproj: pbxproj)

        let nativeTargets = try generateTargets(project: project,
                                                pbxproj: pbxproj,
                                                pbxProject: pbxProject,
                                                groups: groups,
                                                fileElements: fileElements,
                                                sourceRootPath: sourceRootPath,
                                                options: options,
                                                graph: graph)

        return try write(xcodeprojPath: xcodeprojPath,
                         nativeTargets: nativeTargets,
                         workspace: workspace,
                         pbxproj: pbxproj,
                         project: project,
                         graph: graph)
    }

    // MARK: - Fileprivate

    fileprivate func generatePbxproject(project: Project,
                                        configurationList: XCConfigurationList,
                                        groups: ProjectGroups,
                                        pbxproj: PBXProj) throws -> PBXProject {
        let pbxProject = PBXProject(name: project.name,
                                    buildConfigurationList: configurationList,
                                    compatibilityVersion: Xcode.Default.compatibilityVersion,
                                    mainGroup: groups.main,
                                    developmentRegion: Xcode.Default.developmentRegion,
                                    hasScannedForEncodings: 0,
                                    knownRegions: ["en"],
                                    productsGroup: groups.products,
                                    projectDirPath: "",
                                    projects: [],
                                    projectRoots: [],
                                    targets: [])
        pbxproj.add(object: pbxProject)
        pbxproj.rootObject = pbxProject
        return pbxProject
    }

    fileprivate func generateTargets(project: Project,
                                     pbxproj: PBXProj,
                                     pbxProject: PBXProject,
                                     groups: ProjectGroups,
                                     fileElements: ProjectFileElements,
                                     sourceRootPath: AbsolutePath,
                                     options: GenerationOptions,
                                     graph: Graphing) throws -> [String: PBXNativeTarget] {
        var nativeTargets: [String: PBXNativeTarget] = [:]
        try project.targets.forEach { target in
            let nativeTarget = try targetGenerator.generateTarget(target: target,
                                                                  pbxproj: pbxproj,
                                                                  pbxProject: pbxProject,
                                                                  groups: groups,
                                                                  fileElements: fileElements,
                                                                  path: project.path,
                                                                  sourceRootPath: sourceRootPath,
                                                                  options: options,
                                                                  graph: graph,
                                                                  system: system)
            nativeTargets[target.name] = nativeTarget
        }

        /// Target dependencies
        try targetGenerator.generateTargetDependencies(path: project.path,
                                                       targets: project.targets,
                                                       nativeTargets: nativeTargets,
                                                       graph: graph)
        return nativeTargets
    }

    fileprivate func write(xcodeprojPath: AbsolutePath,
                           nativeTargets: [String: PBXNativeTarget],
                           workspace: XCWorkspace,
                           pbxproj: PBXProj,
                           project: Project,
                           graph: Graphing) throws -> GeneratedProject {
        var generatedProject: GeneratedProject!

        try fileHandler.inTemporaryDirectory { temporaryPath in

            try writeXcodeproj(workspace: workspace,
                               pbxproj: pbxproj,
                               xcodeprojPath: temporaryPath)
            generatedProject = GeneratedProject(path: temporaryPath,
                                                targets: nativeTargets,
                                                name: xcodeprojPath.components.last!)
            try writeSchemes(project: project,
                             generatedProject: generatedProject,
                             graph: graph)
            try fileHandler.replace(xcodeprojPath, with: temporaryPath)
        }

        return generatedProject.at(path: xcodeprojPath)
    }

    fileprivate func writeXcodeproj(workspace: XCWorkspace,
                                    pbxproj: PBXProj,
                                    xcodeprojPath: AbsolutePath) throws {
        let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxproj)
        try xcodeproj.write(path: xcodeprojPath.path)
    }

    fileprivate func writeSchemes(project: Project,
                                  generatedProject: GeneratedProject,
                                  graph: Graphing) throws {
        try schemesGenerator.generateTargetSchemes(project: project,
                                                   generatedProject: generatedProject)
        try schemesGenerator.generateProjectScheme(project: project,
                                                   generatedProject: generatedProject,
                                                   graph: graph)
    }
}
