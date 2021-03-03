import Foundation
import TSCBasic
import TuistCore
import XcodeProj

@testable import TuistGenerator

public extension ProjectDescriptor {
    static func test(path: AbsolutePath = AbsolutePath("/Test"),
                     xcodeprojPath: AbsolutePath? = nil,
                     schemes: [SchemeDescriptor] = [],
                     sideEffects: [SideEffectDescriptor] = []) -> ProjectDescriptor
    {
        let mainGroup = PBXGroup()
        let configurationList = XCConfigurationList()
        let pbxProject = PBXProject(
            name: "Test",
            buildConfigurationList: configurationList,
            compatibilityVersion: "1",
            mainGroup: mainGroup
        )
        let pbxproj = PBXProj(
            objectVersion: 50,
            archiveVersion: 10
        )
        pbxproj.add(object: mainGroup)
        pbxproj.add(object: pbxProject)
        pbxproj.add(object: configurationList)
        pbxproj.rootObject = pbxProject
        let xcodeProj = XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj)
        return ProjectDescriptor(
            path: path,
            xcodeprojPath: xcodeprojPath ?? path.appending(component: "Test.xcodeproj"),
            xcodeProj: xcodeProj,
            schemeDescriptors: schemes,
            sideEffectDescriptors: sideEffects
        )
    }
}
