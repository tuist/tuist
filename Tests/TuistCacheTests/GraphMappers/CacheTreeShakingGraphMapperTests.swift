import Foundation
import TSCBasic
import TuistGraph
import XCTest
@testable import TuistCache
@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class CacheTreeShakingGraphMapperTests: TuistUnitTestCase {
    var subject: CacheTreeShakingGraphMapper!

    override func setUp() {
        super.setUp()
        subject = CacheTreeShakingGraphMapper()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_map_removes_projects_when_all_its_targets_are_pruned() throws {
        // Given: Graph
        let target = Target.test(prune: true)
        let project = Project.test(targets: [target])
        let targetNode = TargetNode.test(project: project, target: target)
        let graph = Graph.test(entryNodes: [targetNode],
                               projects: [project],
                               targets: [project.path: [targetNode]])

        // Given: ValueGraph
        let valueGraph = ValueGraph.test(path: project.path,
                                         projects: [project.path: project],
                                         targets: [project.path: [target.name: target]],
                                         dependencies: [:])

        // When
        let (gotGraph, gotSideEffects) = try subject.map(graph: graph)
        let (gotValueGraph, gotValueSideEffects) = try subject.map(graph: valueGraph)

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertEmpty(gotGraph.projects)
        XCTAssertEmpty(gotGraph.targets.flatMap(\.value))

        XCTAssertEmpty(gotValueSideEffects)
        XCTAssertEmpty(gotValueGraph.projects.values)
        XCTAssertEmpty(gotValueGraph.targets.values.flatMap(\.values))
    }

    func test_map_removes_pruned_targets_from_projects() throws {
        // Given
        let firstTarget = Target.test(name: "first", prune: false)
        let secondTarget = Target.test(name: "second", prune: true)
        let project = Project.test(targets: [firstTarget, secondTarget])
        let firstTargetNode = TargetNode.test(project: project, target: firstTarget)
        let secondTargetNode = TargetNode.test(project: project, target: secondTarget)
        let graph = Graph.test(entryNodes: [firstTargetNode, secondTargetNode],
                               projects: [project],
                               targets: [project.path: [firstTargetNode, secondTargetNode]])

        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: project.path,
                                         projects: [project.path: project],
                                         targets: [project.path: [firstTarget.name: firstTarget, secondTarget.name: secondTarget]],
                                         dependencies: [:])

        // When
        let (gotGraph, gotSideEffects) = try subject.map(graph: graph)
        let (gotValueGraph, gotValueSideEffects) = try subject.map(graph: valueGraph)

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertEqual(gotGraph.projects.count, 1)
        let targets = gotGraph.targets.flatMap(\.value)
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first, firstTargetNode)

        XCTAssertEmpty(gotValueSideEffects)
        XCTAssertEqual(gotValueGraph.projects.count, 1)
        let valueTargets = gotValueGraph.targets.flatMap(\.value)
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
        let targetNode = TargetNode.test(project: project, target: target)
        let graph = Graph.test(entryNodes: [targetNode],
                               projects: [project],
                               targets: [project.path: [targetNode]])

        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: project.path,
                                         projects: [project.path: project],
                                         targets: [project.path: [target.name: target]],
                                         dependencies: [:])

        // When
        let (gotGraph, gotSideEffects) = try subject.map(graph: graph)
        let (gotValueGraph, gotValueSideEffects) = try subject.map(graph: valueGraph)

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertEqual(gotGraph.projects.count, 0)
        let projectSchemes = gotGraph.projects.first?.schemes ?? []
        XCTAssertEmpty(projectSchemes)
        let targets = gotGraph.targets.flatMap(\.value)
        XCTAssertEqual(targets.count, 0)

        XCTAssertEmpty(gotValueSideEffects)
        XCTAssertEqual(gotValueGraph.projects.count, 0)
        let valueProjectSchemes = gotValueGraph.projects.values.first?.schemes ?? []
        XCTAssertEmpty(valueProjectSchemes)
        let valueTargets = gotValueGraph.targets.flatMap(\.value)
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
        let targetNode = TargetNode.test(project: project, target: target)
        let workspace = Workspace.test(path: path,
                                       projects: [project.path, removedProjectPath])
        let graph = Graph.test(entryPath: path,
                               entryNodes: [targetNode],
                               workspace: workspace,
                               projects: [project],
                               targets: [project.path: [targetNode]])

        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: project.path,
                                         projects: [project.path: project],
                                         targets: [project.path: [target.name: target]],
                                         dependencies: [:])

        // When
        let (gotGraph, _) = try subject.map(graph: graph)
        let (gotValueGraph, _) = try subject.map(graph: valueGraph)

        // Then
        XCTAssertFalse(gotGraph.workspace.projects.contains(removedProjectPath))
        XCTAssertFalse(gotValueGraph.workspace.projects.contains(removedProjectPath))
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
        let targetNode = TargetNode.test(project: project, target: target)
        let workspace = Workspace.test(path: path,
                                       projects: [project.path, removedProjectPath],
                                       schemes: schemes)
        let graph = Graph.test(entryPath: path,
                               entryNodes: [targetNode],
                               workspace: workspace,
                               projects: [project],
                               targets: [project.path: [targetNode]])

        // Given: Value Graph
        let valueGraph = ValueGraph.test(path: project.path,
                                         projects: [project.path: project],
                                         targets: [project.path: [target.name: target]],
                                         dependencies: [:])

        // When
        let (gotGraph, _) = try subject.map(graph: graph)
        let (gotValueGraph, _) = try subject.map(graph: valueGraph)

        // Then
        XCTAssertEmpty(gotGraph.workspace.schemes)
        XCTAssertEmpty(gotValueGraph.workspace.schemes)
    }
}
