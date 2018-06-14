import Basic
import Foundation
import xcodeproj

/// Project generation protocol.
protocol ProjectGenerating: AnyObject {
    /// Generates the Xcode project from the spec.
    ///
    /// - Parameters:
    ///   - project: project specification.
    ///   - sourceRootPath: path to the folder that contains the project that is being generated.
    ///     If it's not specified, it'll use the same folder where the spec is defined.
    ///   - context: generation context.
    ///   - options: generation options.
    /// - Returns: the path where the project has been generated.
    /// - Throws: an error if the generation fails.
    func generate(project: Project, sourceRootPath: AbsolutePath?, context: GeneratorContexting, options: GenerationOptions) throws -> AbsolutePath
}

/// Project generator.
final class ProjectGenerator: ProjectGenerating {
    /// Target generator.
    let targetGenerator: TargetGenerating

    /// Config generator.
    let configGenerator: ConfigGenerating

    /// Initializes the generator with sub-generators.
    ///
    /// - Parameters:
    ///   - targetGenerator: target generator.
    ///   - configGenerator: config generator.
    init(targetGenerator: TargetGenerating = TargetGenerator(),
         configGenerator: ConfigGenerating = ConfigGenerator()) {
        self.targetGenerator = targetGenerator
        self.configGenerator = configGenerator
    }

    func generate(project: Project,
                  sourceRootPath: AbsolutePath? = nil,
                  context: GeneratorContexting,
                  options: GenerationOptions) throws -> AbsolutePath {
        context.printer.print("Generating project \(project.name)")

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
        let groups = ProjectGroups.generate(project: project, objects: pbxproj.objects, sourceRootPath: sourceRootPath)
        let fileElements = ProjectFileElements()
        fileElements.generateProjectFiles(project: project,
                                          graph: context.graph,
                                          groups: groups,
                                          objects: pbxproj.objects,
                                          sourceRootPath: sourceRootPath)

        // Configuration list
        let configurationListReference = try configGenerator.generateProjectConfig(project: project,
                                                                                   objects: pbxproj.objects,
                                                                                   fileElements: fileElements,
                                                                                   options: options)

        /// Generate project object.
        let pbxProject = PBXProject(name: project.name,
                                    buildConfigurationListReference: configurationListReference,
                                    compatibilityVersion: Xcode.Default.compatibilityVersion,
                                    mainGroup: groups.main.reference,
                                    developmentRegion: Xcode.Default.developmentRegion,
                                    hasScannedForEncodings: 0,
                                    knownRegions: ["en"],
                                    productRefGroup: groups.products.reference,
                                    projectDirPath: "",
                                    projectReferences: [],
                                    projectRoots: [],
                                    targetsReferences: [],
                                    attributes: [:])
        let projectReference = pbxproj.objects.addObject(pbxProject)
        pbxproj.rootObjectReference = projectReference

        /// Manifests target
        try targetGenerator.generateManifestsTarget(project: project,
                                                    pbxproj: pbxproj,
                                                    pbxProject: pbxProject,
                                                    groups: groups,
                                                    sourceRootPath: sourceRootPath,
                                                    context: context,
                                                    options: options)

        /// Native targets
        var nativeTargets: [String: PBXNativeTarget] = [:]
        try project.targets.forEach { target in
            let nativeTarget = try targetGenerator.generateTarget(target: target,
                                                                  objects: pbxproj.objects,
                                                                  pbxProject: pbxProject,
                                                                  groups: groups,
                                                                  fileElements: fileElements,
                                                                  context: context,
                                                                  path: project.path,
                                                                  sourceRootPath: sourceRootPath,
                                                                  options: options)
            nativeTargets[target.name] = nativeTarget
        }

        /// Target dependencies
        try targetGenerator.generateTargetDependencies(path: project.path,
                                                       targets: project.targets,
                                                       nativeTargets: nativeTargets,
                                                       graph: context.graph)

        /// Write.
        let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxproj)
        try xcodeproj.write(path: xcodeprojPath)
        return xcodeprojPath
    }
}
