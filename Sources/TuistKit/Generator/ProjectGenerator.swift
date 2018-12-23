import Basic
import Foundation
import TuistCore
import xcodeproj

protocol ProjectGenerating: AnyObject {
    func generate(project: Project,
                  options: GenerationOptions,
                  graph: Graphing,
                  sourceRootPath: AbsolutePath?,
                  system: Systeming,
                  printer: Printing,
                  resourceLocator: ResourceLocating) throws -> GeneratedProject
}

final class ProjectGenerator: ProjectGenerating {
    // MARK: - Attributes

    let targetGenerator: TargetGenerating
    let configGenerator: ConfigGenerating

    // MARK: - Init

    init(targetGenerator: TargetGenerating = TargetGenerator(),
         configGenerator: ConfigGenerating = ConfigGenerator()) {
        self.targetGenerator = targetGenerator
        self.configGenerator = configGenerator
    }

    // MARK: - ProjectGenerating

    func generate(project: Project,
                  options: GenerationOptions,
                  graph: Graphing,
                  sourceRootPath: AbsolutePath? = nil,
                  system: Systeming = System(),
                  printer: Printing = Printer(),
                  resourceLocator: ResourceLocating = ResourceLocator()) throws -> GeneratedProject {
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
        fileElements.generateProjectFiles(project: project,
                                          graph: graph,
                                          groups: groups,
                                          pbxproj: pbxproj,
                                          sourceRootPath: sourceRootPath)

        // Configuration list
        let configurationList = try configGenerator.generateProjectConfig(project: project,
                                                                          pbxproj: pbxproj,
                                                                          fileElements: fileElements,
                                                                          options: options)

        /// Generate project object.
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

        /// Manifests target
        try targetGenerator.generateManifestsTarget(project: project,
                                                    pbxproj: pbxproj,
                                                    pbxProject: pbxProject,
                                                    groups: groups,
                                                    sourceRootPath: sourceRootPath,
                                                    options: options,
                                                    resourceLocator: resourceLocator)

        /// Native targets
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
                                                                  resourceLocator: resourceLocator,
                                                                  system: system)
            nativeTargets[target.name] = nativeTarget
        }

        /// Target dependencies
        try targetGenerator.generateTargetDependencies(path: project.path,
                                                       targets: project.targets,
                                                       nativeTargets: nativeTargets,
                                                       graph: graph)

        /// Write.
        let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxproj)
        try xcodeproj.write(path: xcodeprojPath.path)

        return GeneratedProject(path: xcodeprojPath,
                                targets: nativeTargets)
    }
}
