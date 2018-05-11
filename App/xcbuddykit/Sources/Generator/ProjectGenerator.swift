import Basic
import Foundation
import xcodeproj

protocol ProjectGenerating: AnyObject {
    func generate(project: Project, context: GeneratorContexting) throws -> AbsolutePath
}

final class ProjectGenerator: ProjectGenerating {
    let targetGenerator: TargetGenerating

    init(targetGenerator: TargetGenerating = TargetGenerator()) {
        self.targetGenerator = targetGenerator
    }

    func generate(project: Project, context: GeneratorContexting) throws -> AbsolutePath {
        context.printer.print("Generating project \(project.name)")
        let workspaceData = XCWorkspaceData(children: [])
        let workspace = XCWorkspace(data: workspaceData)
        let pbxproj = PBXProj(objectVersion: Xcode.Default.objectVersion,
                              archiveVersion: Xcode.LastKnown.archiveVersion,
                              classes: [:])

        /// Configurations.
        let debugConfiguration = XCBuildConfiguration(name: "Debug")
        let debugConfigurationReference = pbxproj.objects.addObject(debugConfiguration)
        let releaseConfiguration = XCBuildConfiguration(name: "Release")
        let releaseConfigurationReference = pbxproj.objects.addObject(releaseConfiguration)

        let configurationList = XCConfigurationList(buildConfigurations: [])
        let configurationListReference = pbxproj.objects.addObject(configurationList)
        configurationList.buildConfigurations.append(debugConfigurationReference)
        configurationList.buildConfigurations.append(releaseConfigurationReference)

        /// Project groups.
        let mainGroup = PBXGroup(children: [], sourceTree: .group)
        let mainGroupReference = pbxproj.objects.addObject(mainGroup)
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

        /// Write.
        let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxproj)
        let xcodeprojPath = project.path.appending(component: "\(project.name).xcodeproj")
        try xcodeproj.write(path: xcodeprojPath)
        return xcodeprojPath
    }
}
