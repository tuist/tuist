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
    /// - Returns: the path where the project has been generated.
    /// - Throws: an error if the generation fails.
    func generate(project: Project, sourceRootPath: AbsolutePath?, context: GeneratorContexting) throws -> AbsolutePath
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
                  context: GeneratorContexting) throws -> AbsolutePath {
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

        /// Main group
        let mainGroup = PBXGroup(children: [],
                                 sourceTree: .group,
                                 path: project.path.relative(to: sourceRootPath).asString)
        let mainGroupReference = pbxproj.objects.addObject(mainGroup)

        // Configuration
        let configurationListReference = try configGenerator.generateProjectConfig(project: project,
                                                                                   pbxproj: pbxproj,
                                                                                   mainGroup: mainGroup,
                                                                                   sourceRootPath: sourceRootPath,
                                                                                   context: context)

        /// Products group
        let productsGroup = PBXGroup(children: [], sourceTree: .buildProductsDir, name: "Products")
        let productsGroupReference = pbxproj.objects.addObject(productsGroup)
        mainGroup.children.append(productsGroupReference)

        /// Generate project object.
        let pbxProject = PBXProject(name: project.name,
                                    buildConfigurationList: configurationListReference,
                                    compatibilityVersion: Xcode.Default.compatibilityVersion,
                                    mainGroup: mainGroupReference,
                                    developmentRegion: Xcode.Default.developmentRegion,
                                    hasScannedForEncodings: 0,
                                    knownRegions: ["en"],
                                    productRefGroup: productsGroupReference,
                                    projectDirPath: "",
                                    projectReferences: [],
                                    projectRoots: [],
                                    targets: [],
                                    attributes: [:])
        let projectReference = pbxproj.objects.addObject(pbxProject)
        pbxproj.rootObject = projectReference

        /// Targets
        try targetGenerator.generateManifestsTarget(project: project,
                                                    pbxproj: pbxproj,
                                                    pbxProject: pbxProject,
                                                    mainGroup: mainGroup,
                                                    productsGroup: productsGroup,
                                                    sourceRootPath: sourceRootPath,
                                                    context: context)

        /// Write.
        let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxproj)
        try xcodeproj.write(path: xcodeprojPath)
        return xcodeprojPath
    }
}
