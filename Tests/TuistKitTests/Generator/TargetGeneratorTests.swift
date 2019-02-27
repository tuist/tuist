import Basic
import Foundation
import xcodeproj
import XCTest
@testable import TuistKit

final class TargetGeneratorTests: XCTestCase {
    var subject: TargetGenerator!

    override func setUp() {
        super.setUp()
        subject = TargetGenerator()
    }

    func test_generateTargetDependencies() throws {
        let pbxproj = PBXProj()
        let path = AbsolutePath("/test")
        let targetA = Target.test(name: "TargetA")
        let targetB = Target.test(name: "TargetB")
        let nativeTargetA = PBXNativeTarget(name: "TargetA")
        let nativeTargetB = PBXNativeTarget(name: "TargetB")
        pbxproj.add(object: nativeTargetA)
        pbxproj.add(object: nativeTargetB)
        let configList = XCConfigurationList(buildConfigurations: [])
        pbxproj.add(object: configList)
        let mainGroup = PBXGroup()
        pbxproj.add(object: mainGroup)
        let project = Project.test(path: path,
                                   name: "Project",
                                   targets: [targetA, targetB])
        let pbxProject = PBXProject(name: "Project",
                                    buildConfigurationList: configList,
                                    compatibilityVersion: "0",
                                    mainGroup: mainGroup)
        pbxproj.add(object: pbxProject)
        let graphCache = GraphLoaderCache()
        let targetBNode = TargetNode(project: project,
                                     target: targetA,
                                     dependencies: [])
        let targetANode = TargetNode(project: project,
                                     target: targetA,
                                     dependencies: [targetBNode])
        let graph = Graph.test(cache: graphCache)
        graphCache.targetNodes[path] = [
            "TargetA": targetANode,
            "TargetB": targetBNode,
        ]
        try subject.generateTargetDependencies(path: path,
                                               targets: [targetA, targetB],
                                               nativeTargets: [
                                                   "TargetA": nativeTargetA,
                                                   "TargetB": nativeTargetB,
                                               ],
                                               graph: graph)
        XCTAssertNotNil(nativeTargetA.dependencies.first)
    }
}
