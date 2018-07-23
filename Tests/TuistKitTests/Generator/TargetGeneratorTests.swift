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
        let objects = PBXObjects()
        let path = AbsolutePath("/test")
        let targetA = Target.test(name: "TargetA")
        let targetB = Target.test(name: "TargetB")
        let nativeTargetA = PBXNativeTarget(name: "TargetA")
        let nativeTargetB = PBXNativeTarget(name: "TargetB")
        objects.addObject(nativeTargetA)
        objects.addObject(nativeTargetB)
        let configList = XCConfigurationList(buildConfigurationsReferences: [])
        let configListRef = objects.addObject(configList)
        let mainGroup = PBXGroup()
        let mainGroupRef = objects.addObject(mainGroup)
        let project = Project.test(path: path,
                                   name: "Project",
                                   targets: [targetA, targetB])
        let pbxProject = PBXProject(name: "Project",
                                    buildConfigurationListReference: configListRef,
                                    compatibilityVersion: "0",
                                    mainGroupReference: mainGroupRef)
        objects.addObject(pbxProject)
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
        XCTAssertNotNil(nativeTargetA.dependenciesReferences.first)
    }
}
