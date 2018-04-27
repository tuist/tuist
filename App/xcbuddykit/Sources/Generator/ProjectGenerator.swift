import Basic
import Foundation
import PathKit
import xcproj

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
        let pbxProj = PBXProj(rootObject: "") // The reference gets added later
        let configurationList = XCConfigurationList(buildConfigurations: [])
        let configurationListReference = pbxProj.objects.generateReference(configurationList, project.name)
        pbxProj.objects.addObject(configurationList, reference: configurationListReference)
        let mainGroup = PBXGroup(children: [])
        let mainGroupReference = pbxProj.objects.generateReference(mainGroup, project.name)
        let pbxProject = PBXProject(name: project.name,
                                    buildConfigurationList: configurationListReference,
                                    compatibilityVersion: "Xcode 8.0",
                                    mainGroup: mainGroupReference)
        let projectReference = pbxProj.objects.generateReference(pbxProject, project.name)
        pbxProj.rootObject = projectReference
        let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxProj)
        let xcodeprojPath = project.path.appending(component: "\(project.name).xcodeproj")
        try xcodeproj.write(path: Path(xcodeprojPath.asString))
        return xcodeprojPath
    }
}
