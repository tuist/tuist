import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistCloud
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class CloudInsightsGraphMapperTests: TuistUnitTestCase {
    var subject: CloudInsightsGraphMapper!

    override func setUp() {
        super.setUp()
        subject = CloudInsightsGraphMapper()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_map_sets_the_build_phases() throws {
        // Given
        let project = Project.test()
        let targetA = Target.test(name: "A")
        let targetANode = TargetNode(project: project, target: targetA, dependencies: [])
        let targetB = Target.test(name: "B")
        let targetBNode = TargetNode(project: project, target: targetB, dependencies: [])
        let graph = Graph.test(entryPath: project.path,
                               entryNodes: [targetANode, targetBNode],
                               projects: [project],
                               targets: [project.path: [targetANode, targetBNode]])

        // When
        let (mappedGraph, _) = try subject.map(graph: graph)

        // Then

        let targets = mappedGraph.entryNodes.compactMap { $0 as? TargetNode }.map { $0.target }
        XCTAssertEqual(targets.count, 2)
        let preAction = TargetAction(name: "[Tuist] Track target build start",
                                     order: .pre,
                                     tool: "tuist",
                                     path: nil,
                                     arguments: ["cloud", "start-target-build"])
        let postAction = TargetAction(name: "[Tuist] Track target build finish",
                                      order: .post,
                                      tool: "tuist",
                                      path: nil,
                                      arguments: ["cloud", "finish-target-build"])
        let firstTarget = targets.first!
        let lastTarget = targets.last!

        XCTAssertTrue(firstTarget.actions.contains(preAction))
        XCTAssertTrue(firstTarget.actions.contains(postAction))
        XCTAssertTrue(lastTarget.actions.contains(preAction))
        XCTAssertTrue(lastTarget.actions.contains(postAction))
    }

    func test_when_value_graph() throws {
        // Given
        let project = Project.test()
        let targetA = Target.test(name: "A")
        let targetB = Target.test(name: "B")
        let graph = ValueGraph.test(projects: [project.path: project],
                                    targets: [project.path: [targetA.name: targetA, targetB.name: targetB]])

        // When
        let (mappedGraph, _) = try subject.map(graph: graph)

        // Then
        let targets = mappedGraph.targets.values.flatMap { $0.values }
        let preAction = TargetAction(name: "[Tuist] Track target build start",
                                     order: .pre,
                                     tool: "tuist",
                                     path: nil,
                                     arguments: ["cloud", "start-target-build"])
        let postAction = TargetAction(name: "[Tuist] Track target build finish",
                                      order: .post,
                                      tool: "tuist",
                                      path: nil,
                                      arguments: ["cloud", "finish-target-build"])
        let firstTarget = targets.first!
        let lastTarget = targets.last!
        XCTAssertEqual(firstTarget.preActions, [preAction])
        XCTAssertEqual(firstTarget.postActions, [postAction])
        XCTAssertEqual(lastTarget.preActions, [preAction])
        XCTAssertEqual(lastTarget.postActions, [postAction])
    }
}
