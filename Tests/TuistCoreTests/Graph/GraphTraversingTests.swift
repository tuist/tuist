import Foundation
import Path
import TuistSupport
import XcodeGraph
import XCTest
@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class GraphTraversingTests: TuistUnitTestCase {
    func test_filterIncludedTargets_when_graph_is_empty() {
        // Given
        let graph = Graph.test()
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.filterIncludedTargets(
            basedOn: subject.allTargets(),
            testPlan: nil,
            includedTargets: Set(),
            excludedTargets: Set(),
            excludingExternalTargets: false
        )

        // Then
        XCTAssertEqual(got, [])
    }

    func test_filterIncludedTargets_when_included_targets_is_unused_tag() {
        // Given
        let targetA = Target.test(name: "a")
        let targetB = Target.test(name: "b")
        let project = Project.test(targets: [targetA, targetB])
        let graph = Graph.test(
            projects: [
                project.path: project,
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.filterIncludedTargets(
            basedOn: subject.allTargets(),
            testPlan: nil,
            includedTargets: [.tagged("tag")],
            excludedTargets: [],
            excludingExternalTargets: false
        )

        // Then
        let expectedTargetA = GraphTarget(path: project.path, target: targetA, project: project)
        XCTAssertEqual(got, [])
    }

    func test_filterIncludedTargets_when_included_targets_is_tag() {
        // Given
        let targetA = Target.test(name: "a", metadata: .test(tags: ["tag"]))
        let targetB = Target.test(name: "b")
        let project = Project.test(targets: [targetA, targetB])
        let graph = Graph.test(
            projects: [
                project.path: project,
            ]
        )
        let subject = GraphTraverser(graph: graph)

        // When
        let got = subject.filterIncludedTargets(
            basedOn: subject.allTargets(),
            testPlan: nil,
            includedTargets: [.tagged("tag")],
            excludedTargets: [],
            excludingExternalTargets: false
        )

        // Then
        let expectedTargetA = GraphTarget(path: project.path, target: targetA, project: project)
        XCTAssertEqual(got, [expectedTargetA])
    }
}
