import Foundation
import TSCBasic
import TuistGraph
import XCTest
@testable import TuistCache
@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class TreeShakePrunedTargetsGraphMapperTests: TuistUnitTestCase {
    var subject: TreeShakePrunedTargetsGraphMapper!

    override func setUp() {
        super.setUp()
        subject = TreeShakePrunedTargetsGraphMapper()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_map_removes_projects_when_all_its_targets_are_pruned() throws {
        // Given
        let target = Target.test(prune: true)
        let project = Project.test(targets: [target])

        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            targets: [project.path: [target.name: target]]
        )

        let expectedGraph = Graph.test(
            path: project.path,
            projects: [:],
            targets: [:]
        )

        // When
        let (gotGraph, gotSideEffects) = try subject.map(graph: graph)

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertEqual(
            gotGraph,
            expectedGraph
        )
    }

    func test_map_removes_pruned_targets_from_projects() throws {
        // Given
        let firstTarget = Target.test(name: "first", prune: false)
        let secondTarget = Target.test(name: "second", prune: true)
        let project = Project.test(targets: [firstTarget, secondTarget])

        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            targets: [project.path: [firstTarget.name: firstTarget, secondTarget.name: secondTarget]],
            dependencies: [:]
        )

        // When
        let (gotGraph, gotValueSideEffects) = try subject.map(graph: graph)

        // Then
        XCTAssertEmpty(gotValueSideEffects)
        XCTAssertEqual(gotGraph.projects.count, 1)
        let valueTargets = gotGraph.targets.flatMap(\.value)
        XCTAssertEqual(valueTargets.count, 1)
        XCTAssertEqual(valueTargets.first?.value, firstTarget)
    }

    func test_map_removes_project_schemes_with_whose_all_targets_have_been_removed() throws {
        // Given
        let path = AbsolutePath("/project")
        let target = Target.test(name: "first", prune: true)
        let schemes: [Scheme] = [
            .test(buildAction: .test(targets: [.init(projectPath: path, name: target.name)])),
        ]
        let project = Project.test(path: path, targets: [target], schemes: schemes)

        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            targets: [project.path: [target.name: target]],
            dependencies: [:]
        )

        // When
        let (gotGraph, gotSideEffects) = try subject.map(graph: graph)

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertEqual(gotGraph.projects.count, 0)
        let valueProjectSchemes = gotGraph.projects.values.first?.schemes ?? []
        XCTAssertEmpty(valueProjectSchemes)
        let valueTargets = gotGraph.targets.flatMap(\.value)
        XCTAssertEqual(valueTargets.count, 0)
    }

    func test_map_removes_the_workspace_projects_that_no_longer_exist() throws {
        // Given
        let path = AbsolutePath("/project")
        let removedProjectPath = AbsolutePath.root.appending(component: "Other")
        let target = Target.test(name: "first", prune: true)
        let schemes: [Scheme] = [
            .test(buildAction: .test(targets: [.init(projectPath: path, name: target.name)])),
        ]
        let project = Project.test(path: path, targets: [target], schemes: schemes)
        let workspace = Workspace.test(
            path: path,
            projects: [project.path, removedProjectPath]
        )

        // Given
        let graph = Graph.test(
            path: project.path,
            workspace: workspace,
            projects: [project.path: project],
            targets: [project.path: [target.name: target]],
            dependencies: [:]
        )

        // When
        let (gotGraph, _) = try subject.map(graph: graph)

        // Then
        XCTAssertFalse(gotGraph.workspace.projects.contains(removedProjectPath))
    }

    func test_map_treeshakes_the_workspace_schemes() throws {
        // Given
        let path = AbsolutePath("/project")
        let removedProjectPath = AbsolutePath.root.appending(component: "Other")
        let target = Target.test(name: "first", prune: true)
        let schemes: [Scheme] = [
            .test(buildAction: .test(targets: [.init(projectPath: path, name: target.name)])),
        ]
        let project = Project.test(path: path, targets: [target], schemes: [])
        let workspace = Workspace.test(
            path: path,
            projects: [project.path, removedProjectPath],
            schemes: schemes
        )

        let graph = Graph.test(
            path: project.path,
            workspace: workspace,
            projects: [project.path: project],
            targets: [project.path: [target.name: target]],
            dependencies: [:]
        )

        // When
        let (gotGraph, _) = try subject.map(graph: graph)

        // Then
        XCTAssertEmpty(gotGraph.workspace.schemes)
    }

    func test_map_removes_pruned_targets_from_scheme() throws {
        // Given
        let path = AbsolutePath("/project")
        let targets = [
            Target.test(name: "first", prune: true),
            Target.test(name: "second", prune: false),
            Target.test(name: "third", prune: true),
        ]
        let scheme = Scheme.test(
            name: "Scheme",
            buildAction: .test(targets: targets.map { TargetReference(projectPath: path, name: $0.name) }),
            testAction: .test(
                targets: targets.map { TestableTarget(target: TargetReference(projectPath: path, name: $0.name)) },
                coverage: true,
                codeCoverageTargets: targets.map { TargetReference(projectPath: path, name: $0.name) }
            )
        )
        let project = Project.test(path: path, targets: targets, schemes: [scheme])
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            targets: [project.path: Dictionary(uniqueKeysWithValues: targets.map { ($0.name, $0) })]
        )

        let unprunedTargets = targets.filter { !$0.prune }
        let schemeWithUnprunedTargets = Scheme.test(
            name: "Scheme",
            buildAction: .test(targets: unprunedTargets.map { TargetReference(projectPath: path, name: $0.name) }),
            testAction: .test(
                targets: unprunedTargets.map { TestableTarget(target: TargetReference(projectPath: path, name: $0.name)) },
                coverage: true,
                codeCoverageTargets: unprunedTargets.map { TargetReference(projectPath: path, name: $0.name) }
            )
        )
        let expectedProject = Project.test(path: path, targets: unprunedTargets, schemes: [schemeWithUnprunedTargets])
        let expectedGraph = Graph.test(
            path: expectedProject.path,
            projects: [expectedProject.path: expectedProject],
            targets: [expectedProject.path: Dictionary(uniqueKeysWithValues: unprunedTargets.map { ($0.name, $0) })]
        )

        // When
        let (gotGraph, _) = try subject.map(graph: graph)

        // Then
        XCTAssertEqual(gotGraph, expectedGraph)
    }
}
