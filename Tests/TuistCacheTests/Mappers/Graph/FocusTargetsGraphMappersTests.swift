import Foundation
import TSCBasic
import TuistGraph
import XCTest
@testable import TuistCache
@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class FocusTargetsGraphMappersTests: TuistUnitTestCase {
    func test_map_when_included_targets_is_empty_no_targets_are_pruned() throws {
        // Given
        let targetNames = ["foo", "bar", "baz"].shuffled()
        let aTarget = Target.test(name: targetNames[0])
        let bTarget = Target.test(name: targetNames[1])
        let cTarget = Target.test(name: targetNames[2])
        let subject = FocusTargetsGraphMappers(includedTargets: Set())
        let path = try temporaryPath()
        let project = Project.test(path: path)
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                path: [
                    aTarget.name: aTarget,
                    bTarget.name: bTarget,
                    cTarget.name: cTarget,
                ],
            ],
            dependencies: [
                .target(name: bTarget.name, path: path): [
                    .target(name: aTarget.name, path: path),
                ],
                .target(name: cTarget.name, path: path): [
                    .target(name: bTarget.name, path: path),
                ],
            ]
        )

        // When
        let (gotGraph, gotSideEffects) = try subject.map(graph: graph)

        let pruningTargets = gotGraph.targets[path]?.values.filter(\.prune) ?? []
        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertEmpty(pruningTargets.map(\.name))
    }

    func test_map_when_included_targets_is_target_with_no_dependency_all_other_targets_are_pruned() throws {
        // Given
        let targetNames = ["foo", "bar", "baz"].shuffled()
        let aTarget = Target.test(name: targetNames[0])
        let bTarget = Target.test(name: targetNames[1])
        let cTarget = Target.test(name: targetNames[2])
        let subject = FocusTargetsGraphMappers(includedTargets: [aTarget.name])
        let path = try temporaryPath()
        let project = Project.test(path: path)
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                path: [
                    aTarget.name: aTarget,
                    bTarget.name: bTarget,
                    cTarget.name: cTarget,
                ],
            ],
            dependencies: [
                .target(name: bTarget.name, path: path): [
                    .target(name: aTarget.name, path: path),
                ],
                .target(name: cTarget.name, path: path): [
                    .target(name: bTarget.name, path: path),
                ],
            ]
        )

        // When
        let (gotGraph, gotSideEffects) = try subject.map(graph: graph)

        let expectingTargets = [bTarget, cTarget]
        let pruningTargets = gotGraph.targets[path]?.values.filter(\.prune) ?? []
        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertEqual(
            pruningTargets.map(\.name).sorted(),
            expectingTargets.map(\.name).sorted()
        )
    }

    func test_map_when_included_targets_is_target_with_dependencies_all_non_dependant_targets_are_pruned() throws {
        // Given
        let targetNames = ["foo", "bar", "baz"].shuffled()
        let aTarget = Target.test(name: targetNames[0])
        let bTarget = Target.test(name: targetNames[1])
        let cTarget = Target.test(name: targetNames[2])
        let subject = FocusTargetsGraphMappers(includedTargets: [bTarget.name])
        let path = try temporaryPath()
        let project = Project.test(path: path)
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                path: [
                    aTarget.name: aTarget,
                    bTarget.name: bTarget,
                    cTarget.name: cTarget,
                ],
            ],
            dependencies: [
                .target(name: bTarget.name, path: path): [
                    .target(name: aTarget.name, path: path),
                ],
                .target(name: cTarget.name, path: path): [
                    .target(name: bTarget.name, path: path),
                ],
            ]
        )

        // When
        let (gotGraph, gotSideEffects) = try subject.map(graph: graph)

        let expectingTargets = [cTarget]
        let pruningTargets = gotGraph.targets[path]?.values.filter(\.prune) ?? []
        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertEqual(
            pruningTargets.map(\.name).sorted(),
            expectingTargets.map(\.name).sorted()
        )
    }

    func test_map_when_included_targets_is_target_with_no_dependency_but_with_test_target_also_test_target_is_pruned() throws {
        // Given
        let targetNames = ["foo", "bar", "baz"].shuffled()
        let aTarget = Target.test(name: targetNames[0])
        let aTestTarget = Target.test(name: targetNames[0] + "Tests", product: .unitTests)
        let bTarget = Target.test(name: targetNames[1])
        let cTarget = Target.test(name: targetNames[2])
        let subject = FocusTargetsGraphMappers(includedTargets: [aTarget.name])
        let path = try temporaryPath()
        let project = Project.test(path: path)
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                path: [
                    aTestTarget.name: aTestTarget,
                    aTarget.name: aTarget,
                    bTarget.name: bTarget,
                    cTarget.name: cTarget,
                ],
            ],
            dependencies: [
                .target(name: aTestTarget.name, path: path): [
                    .target(name: aTarget.name, path: path),
                ],
                .target(name: bTarget.name, path: path): [
                    .target(name: aTarget.name, path: path),
                ],
                .target(name: cTarget.name, path: path): [
                    .target(name: bTarget.name, path: path),
                ],
            ]
        )

        // When
        let (gotGraph, gotSideEffects) = try subject.map(graph: graph)

        let expectingTargets = [bTarget, cTarget, aTestTarget]
        let pruningTargets = gotGraph.targets[path]?.values.filter(\.prune) ?? []
        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertEqual(
            pruningTargets.map(\.name).sorted(),
            expectingTargets.map(\.name).sorted()
        )
    }
}
