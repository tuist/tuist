import Basic
import Foundation
import TuistCore
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator
@testable import TuistSupportTesting

public final class GenerateInfoPlistGraphMapperTests: TuistUnitTestCase {
    var infoPlistContentProvider: MockInfoPlistContentProvider!
    var subject: GenerateInfoPlistGraphMapper!

    public override func setUp() {
        super.setUp()
        infoPlistContentProvider = MockInfoPlistContentProvider()
        subject = GenerateInfoPlistGraphMapper(infoPlistContentProvider: infoPlistContentProvider)
    }

    public override func tearDown() {
        super.tearDown()
        infoPlistContentProvider = nil
        subject = nil
    }

    func test_map() throws {
        // Given
        let project = Project.test()
        let targetA = Target.test(name: "A", infoPlist: .dictionary(["A": "A_VALUE"]))
        let targetANode = TargetNode.test(project: project, target: targetA)
        let targetB = Target.test(name: "B", infoPlist: .dictionary(["B": "B_VALUE"]))
        let targetBNode = TargetNode.test(project: project, target: targetB)
        let graph = Graph.test(entryPath: project.path,
                               entryNodes: [targetANode, targetBNode],
                               projects: [project],
                               targets: [project.path: [targetANode, targetBNode]])

        // When
        let (mappedGraph, sideEffects) = try subject.map(graph: graph)

        XCTAssertEqual(sideEffects.count, 2)
        XCTAssertEqual(mappedGraph.targets.values.flatMap { $0 }.count, 2)

        try XCTAssertSideEffectsCreateDerivedInfoPlist(named: "A.plist",
                                                       content: ["A": "A_VALUE"],
                                                       projectPath: project.path,
                                                       sideEffects: sideEffects)
        try XCTAssertSideEffectsCreateDerivedInfoPlist(named: "B.plist",
                                                       content: ["B": "B_VALUE"],
                                                       projectPath: project.path,
                                                       sideEffects: sideEffects)
        XCTAssertTargetExistsWithDerivedInfoPlist(named: "A.plist",
                                                  graph: mappedGraph,
                                                  projectPath: project.path)
        XCTAssertTargetExistsWithDerivedInfoPlist(named: "B.plist",
                                                  graph: mappedGraph,
                                                  projectPath: project.path)
    }

    fileprivate func XCTAssertSideEffectsCreateDerivedInfoPlist(named: String,
                                                                content: [String: String],
                                                                projectPath: AbsolutePath,
                                                                sideEffects: [SideEffectDescriptor],
                                                                file: StaticString = #file,
                                                                line: UInt = #line) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: content,
                                                      format: .xml,
                                                      options: 0)

        XCTAssertNotNil(sideEffects.first(where: { sideEffect in
            guard case let SideEffectDescriptor.file(file) = sideEffect else { return false }
            return file.path == projectPath.appending(component: Constants.DerivedFolder.name)
                .appending(component: Constants.DerivedFolder.infoPlists)
                .appending(component: named) && file.contents == data
        }), file: file, line: line)
    }

    fileprivate func XCTAssertTargetExistsWithDerivedInfoPlist(named: String,
                                                               graph: Graph,
                                                               projectPath: AbsolutePath,
                                                               file: StaticString = #file,
                                                               line: UInt = #line) {
        XCTAssertNotNil(graph.targets.values.flatMap { $0 }.first(where: { (targetNode: TargetNode) in
            targetNode.target.infoPlist?.path == projectPath.appending(component: Constants.DerivedFolder.name)
                .appending(component: Constants.DerivedFolder.infoPlists)
                .appending(component: named)
        }), file: file, line: line)
    }
}
