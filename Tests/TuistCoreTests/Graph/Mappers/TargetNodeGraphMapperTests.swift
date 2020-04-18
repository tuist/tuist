import TuistCore
import XCTest
@testable import TuistCoreTesting

class TargetNodeGraphMapperTests: XCTestCase {
    func test_map() {
        // Given
        let subject = TargetNodeGraphMapper { targetNode in
            TargetNode(project: targetNode.project, target: targetNode.target, dependencies: [])
        }

        let targetA = Target.test(name: "TargetA")
        let targetB = Target.test(name: "TargetB")
        let targetC = Target.test(name: "TargetC")
        let project = Project.test(targets: [targetA, targetB, targetC])
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: targetA, dependencies: [targetB]),
                                     (target: targetB, dependencies: [targetC]),
                                     (target: targetC, dependencies: []),
                                 ])

        // When
        let (results, _) = subject.map(graph: graph)

        // Then
        XCTAssertEqual(results.targets(at: project.path).count, 3)
        XCTAssertEqual(results.target(path: project.path, name: "TargetA")?.dependencies.map(\.name), [])
        XCTAssertEqual(results.target(path: project.path, name: "TargetB")?.dependencies.map(\.name), [])
        XCTAssertEqual(results.target(path: project.path, name: "TargetC")?.dependencies.map(\.name), [])
    }

    func test_map_doesNotUpdateOriginal() {
        // Given
        let subject = TargetNodeGraphMapper { targetNode in
            TargetNode(project: targetNode.project, target: targetNode.target, dependencies: [])
        }

        let targetA = Target.test(name: "TargetA")
        let targetB = Target.test(name: "TargetB")
        let targetC = Target.test(name: "TargetC")
        let project = Project.test(targets: [targetA, targetB, targetC])
        let graph = Graph.create(project: project,
                                 dependencies: [
                                     (target: targetA, dependencies: [targetB]),
                                     (target: targetB, dependencies: [targetC]),
                                     (target: targetC, dependencies: []),
                                 ])

        // When
        _ = subject.map(graph: graph)

        // Then
        XCTAssertEqual(graph.targets(at: project.path).count, 3)
        XCTAssertEqual(graph.target(path: project.path, name: "TargetA")?.dependencies.map(\.name), ["TargetB"])
        XCTAssertEqual(graph.target(path: project.path, name: "TargetB")?.dependencies.map(\.name), ["TargetC"])
        XCTAssertEqual(graph.target(path: project.path, name: "TargetC")?.dependencies.map(\.name), [])
    }

    func test_map_removesOrphanedNodes() {
        // Given
        let subject = TargetNodeGraphMapper { targetNode in
            TargetNode(project: targetNode.project, target: targetNode.target, dependencies: [])
        }

        let targetA = Target.test(name: "TargetA")
        let targetB = Target.test(name: "TargetB")
        let targetC = Target.test(name: "TargetC")
        let projectA = Project.test(path: "/test/ProjctA", targets: [targetA])
        let projectB = Project.test(path: "/test/ProjctB", targets: [targetB, targetC])
        let graph = Graph.create(projects: [projectA, projectB],
                                 entryNodes: [targetA],
                                 dependencies: [
                                     (project: projectA, target: targetA, dependencies: [targetB]),
                                     (project: projectB, target: targetB, dependencies: [targetC]),
                                     (project: projectB, target: targetC, dependencies: []),
                                 ])

        // When
        let (results, _) = subject.map(graph: graph)

        // Then
        XCTAssertEqual(results.targets.flatMap { $0.value }.count, 1)
        XCTAssertEqual(results.projects.count, 1)
    }

    func test_map_postMapOrphanedNodesdoNotUpdateOriginal() {
        // Given
        let subject = TargetNodeGraphMapper { targetNode in
            TargetNode(project: targetNode.project, target: targetNode.target, dependencies: [])
        }

        let targetA = Target.test(name: "TargetA")
        let targetB = Target.test(name: "TargetB")
        let targetC = Target.test(name: "TargetC")
        let projectA = Project.test(path: "/test/ProjctA", targets: [targetA])
        let projectB = Project.test(path: "/test/ProjctB", targets: [targetB, targetC])
        let graph = Graph.create(projects: [projectA, projectB],
                                 entryNodes: [targetA],
                                 dependencies: [
                                     (project: projectA, target: targetA, dependencies: [targetB]),
                                     (project: projectB, target: targetB, dependencies: [targetC]),
                                     (project: projectB, target: targetC, dependencies: []),
                                 ])

        // When
        _ = subject.map(graph: graph)

        // Then
        XCTAssertEqual(graph.targets.flatMap { $0.value }.count, 3)
        XCTAssertEqual(graph.projects.count, 2)
    }
}
