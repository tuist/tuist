import Mockable
import Path
import TuistTesting
import XcodeGraph
import XCTest
@testable import TuistCore

final class GraphTraversingTests: TuistUnitTestCase {
    func test_filterIncludedTargets_when_graph_is_empty() {
        // Given
        let subject = MockGraphTraversing()

        given(subject)
            .allTargets()
            .willReturn([])

        // When
        let got = subject.filterIncludedTargets(
            basedOn: subject.allTargets(),
            testPlan: nil,
            includedTargets: [],
            excludedTargets: [],
            excludingExternalTargets: false
        )

        // Then
        XCTAssertEqual(got, [])
    }

    func test_filterIncludedTargets_when_testPlan() {
        // Given
        let targetA = Target.test(name: "Target")
        let targetB = Target.test(name: "TargetTests")
        let project = Project.test(targets: [targetA, targetB])
        let graphTargetA = GraphTarget(path: project.path, target: targetA, project: project)
        let graphTargetB = GraphTarget(path: project.path, target: targetB, project: project)
        let subject = MockGraphTraversing()

        given(subject)
            .allTargets()
            .willReturn([graphTargetA, graphTargetB])
        given(subject)
            .testPlan(name: .any)
            .willReturn(
                TestPlan(
                    path: "/Test.xctestplan",
                    testTargets: [
                        .test(target: .init(projectPath: project.path, name: targetB.name)),
                    ],
                    isDefault: true
                )
            )

        // When
        let got = subject.filterIncludedTargets(
            basedOn: subject.allTargets(),
            testPlan: "Test.xctestplan",
            includedTargets: [],
            excludedTargets: [],
            excludingExternalTargets: false
        )

        // Then
        XCTAssertEqual(got, [graphTargetB])
    }

    func test_filterIncludedTargets_when_excludingExternalTargets() {
        // Given
        let targetA = Target.test(name: "a")
        let targetB = Target.test(name: "b")
        let project = Project.test(targets: [targetA, targetB])
        let graphTargetA = GraphTarget(path: project.path, target: targetA, project: project)
        let graphTargetB = GraphTarget(path: project.path, target: targetB, project: project)
        let subject = MockGraphTraversing()

        given(subject)
            .allTargets()
            .willReturn([graphTargetA, graphTargetB])
        given(subject)
            .allInternalTargets()
            .willReturn([graphTargetA])

        // When
        let got = subject.filterIncludedTargets(
            basedOn: subject.allTargets(),
            testPlan: nil,
            includedTargets: [],
            excludedTargets: [],
            excludingExternalTargets: true
        )

        // Then
        XCTAssertEqual(got, [graphTargetA])
    }

    func test_filterIncludedTargets_when_included_targets_is_unused_tag() {
        // Given
        let targetA = Target.test(name: "a", metadata: .test(tags: ["tag"]))
        let targetB = Target.test(name: "b")
        let project = Project.test(targets: [targetA, targetB])
        let graphTargetA = GraphTarget(path: project.path, target: targetA, project: project)
        let graphTargetB = GraphTarget(path: project.path, target: targetB, project: project)
        let subject = MockGraphTraversing()

        given(subject)
            .allTargets()
            .willReturn([graphTargetA, graphTargetB])

        // When
        let got = subject.filterIncludedTargets(
            basedOn: subject.allTargets(),
            testPlan: nil,
            includedTargets: [.tagged("unused")],
            excludedTargets: [],
            excludingExternalTargets: false
        )

        // Then
        XCTAssertEqual(got, [])
    }

    func test_filterIncludedTargets_when_included_targets_is_name() {
        // Given
        let targetA = Target.test(name: "a", metadata: .test(tags: ["tag"]))
        let targetB = Target.test(name: "b")
        let project = Project.test(targets: [targetA, targetB])
        let graphTargetA = GraphTarget(path: project.path, target: targetA, project: project)
        let graphTargetB = GraphTarget(path: project.path, target: targetB, project: project)
        let subject = MockGraphTraversing()

        given(subject)
            .allTargets()
            .willReturn([graphTargetA, graphTargetB])

        // When
        let got = subject.filterIncludedTargets(
            basedOn: subject.allTargets(),
            testPlan: nil,
            includedTargets: [.named("b")],
            excludedTargets: [],
            excludingExternalTargets: false
        )

        // Then
        XCTAssertEqual(got, [graphTargetB])
    }

    func test_filterIncludedTargets_when_included_targets_is_tag() {
        // Given
        let targetA = Target.test(name: "a", metadata: .test(tags: ["tag"]))
        let targetB = Target.test(name: "b")
        let project = Project.test(targets: [targetA, targetB])
        let graphTargetA = GraphTarget(path: project.path, target: targetA, project: project)
        let graphTargetB = GraphTarget(path: project.path, target: targetB, project: project)
        let subject = MockGraphTraversing()

        given(subject)
            .allTargets()
            .willReturn([graphTargetA, graphTargetB])

        // When
        let got = subject.filterIncludedTargets(
            basedOn: subject.allTargets(),
            testPlan: nil,
            includedTargets: [.tagged("tag")],
            excludedTargets: [],
            excludingExternalTargets: false
        )

        // Then
        XCTAssertEqual(got, [graphTargetA])
    }

    func test_filterIncludedTargets_when_excluded_targets_is_name() {
        // Given
        let targetA = Target.test(name: "a", metadata: .test(tags: ["tag"]))
        let targetB = Target.test(name: "b")
        let project = Project.test(targets: [targetA, targetB])
        let graphTargetA = GraphTarget(path: project.path, target: targetA, project: project)
        let graphTargetB = GraphTarget(path: project.path, target: targetB, project: project)
        let subject = MockGraphTraversing()

        given(subject)
            .allTargets()
            .willReturn([graphTargetA, graphTargetB])

        // When
        let got = subject.filterIncludedTargets(
            basedOn: subject.allTargets(),
            testPlan: nil,
            includedTargets: [],
            excludedTargets: [.named("b")],
            excludingExternalTargets: false
        )

        // Then
        XCTAssertEqual(got, [graphTargetA])
    }

    func test_filterIncludedTargets_when_excluded_targets_is_tag() {
        // Given
        let targetA = Target.test(name: "a", metadata: .test(tags: ["tag"]))
        let targetB = Target.test(name: "b")
        let project = Project.test(targets: [targetA, targetB])
        let graphTargetA = GraphTarget(path: project.path, target: targetA, project: project)
        let graphTargetB = GraphTarget(path: project.path, target: targetB, project: project)
        let subject = MockGraphTraversing()

        given(subject)
            .allTargets()
            .willReturn([graphTargetA, graphTargetB])

        // When
        let got = subject.filterIncludedTargets(
            basedOn: subject.allTargets(),
            testPlan: nil,
            includedTargets: [],
            excludedTargets: [.tagged("tag")],
            excludingExternalTargets: false
        )

        // Then
        XCTAssertEqual(got, [graphTargetB])
    }
}
