
import Basic
import Foundation
import XcodeProj
@testable import TuistGenerator

extension ProjectDescriptor {
    static func test(path: AbsolutePath,
                     xcodeprojPath: AbsolutePath? = nil,
                     schemes: [SchemeDescriptor] = [],
                     sideEffects: [SideEffect] = []) -> ProjectDescriptor {
        let mainGroup = PBXGroup()
        let configurationList = XCConfigurationList()
        let pbxProject = PBXProject(name: "Test",
                                    buildConfigurationList: configurationList,
                                    compatibilityVersion: "1",
                                    mainGroup: mainGroup)
        let pbxproj = PBXProj(objectVersion: 50,
                              archiveVersion: 10)
        pbxproj.add(object: mainGroup)
        pbxproj.add(object: pbxProject)
        pbxproj.add(object: configurationList)
        pbxproj.rootObject = pbxProject
        let xcodeProj = XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj)
        return ProjectDescriptor(path: path,
                                 xcodeprojPath: xcodeprojPath ?? path.appending(component: "Test.xcodeproj"),
                                 xcodeProj: xcodeProj,
                                 schemes: schemes,
                                 sideEffects: sideEffects)
    }
}
