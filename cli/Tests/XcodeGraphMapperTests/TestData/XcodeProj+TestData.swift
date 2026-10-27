import FileSystem
import Foundation
import Path
import PathKit
import XcodeGraph
import XcodeProj

extension XcodeProj {
    static func test(
        projectName: String = "TestProject",
        configurationList: XCConfigurationList = XCConfigurationList.test(
            buildConfigurations: [.testDebug(), .testRelease()]
        ),
        targets: [PBXTarget] = [],
        pbxProj: PBXProj = PBXProj(),
        path: AbsolutePath? = nil
    ) async throws -> XcodeProj {
        pbxProj.add(object: configurationList)
        for config in configurationList.buildConfigurations {
            pbxProj.add(object: config)
        }

        let sourceDirectory = try await FileSystem().makeTemporaryDirectory(prefix: "test")

        // Minimal project setup:
        let mainGroup = PBXGroup.test(
            children: [],
            sourceTree: .group,
            name: "MainGroup",
            path: "/tmp/TestProject"
        ).add(to: pbxProj)

        let projectRef = PBXFileReference
            .test(name: "App", path: "App.xcodeproj")
            .add(to: pbxProj)
        mainGroup.children.append(projectRef)

        let projects = [
            ["B900DB68213936CC004AEC3E": projectRef],
        ]

        let pbxProject = PBXProject.test(
            name: projectName,
            buildConfigurationList: configurationList,
            mainGroup: mainGroup,
            projects: projects,
            targets: targets
        ).add(to: pbxProj)

        pbxProject.mainGroup = mainGroup
        pbxProj.add(object: pbxProject)
        pbxProj.rootObject = pbxProject

        return XcodeProj(
            workspace: XCWorkspace(),
            pbxproj: pbxProj,
            path: path.map(\.pathString).map { Path($0) } ?? Path("\(sourceDirectory)/\(projectName).xcodeproj")
        )
    }
}
