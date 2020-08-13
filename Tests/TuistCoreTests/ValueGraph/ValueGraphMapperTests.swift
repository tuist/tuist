import Foundation
import TuistCore
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class AnyValueGraphMapperTests: TuistUnitTestCase {
    var subject: AnyValueGraphMapper!

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_map() throws {
        // Given
        let graph = ValueGraph.test(name: "graph", path: "/")
        let sideEffect = SideEffectDescriptor.command(.init(command: ["test"]))
        subject = AnyValueGraphMapper(mapper: { (graph) -> (ValueGraph, [SideEffectDescriptor]) in
            var graph = graph
            graph.name = "mapped"
            return (graph, [sideEffect])
        })

        // When
        let (gotGraph, gotSideEffects) = try subject.map(graph: graph)

        // Then
        XCTAssertEqual(gotGraph.name, "mapped")
        XCTAssertEqual(gotSideEffects, [sideEffect])
    }
}

final class ValueGraphProjectMapperTests: TuistUnitTestCase {
    var subject: ValueGraphProjectMapper!

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_map() throws {
        // Given
        let project = Project.test(path: "/", name: "project")
        let target = Target.test(name: "app", product: .app)
        let sideEffect = SideEffectDescriptor.command(.init(command: ["test"]))
        let graph = ValueGraph.test(name: "graph",
                                    path: "/",
                                    projects: [project.path: project],
                                    targets: [project.path: [target.name: target]])
        subject = ValueGraphProjectMapper(projectMapper: AnyValueProjectMapper(mapper: { (project, targets) -> (Project, [String: Target], [SideEffectDescriptor]) in
            var project = project
            project.name = "mapped-project"
            let targets = targets.mapValues { (target) -> Target in
                var target = target
                target.name = "mapped-app"
                return target
            }
            return (project, targets, [sideEffect])
        }))

        // Then
        // When
        let (gotGraph, gotSideEffects) = try subject.map(graph: graph)

        // Then
        XCTAssertEqual(gotGraph.projects.count, 1)
        XCTAssertEqual(gotGraph.projects.values.first?.name, "mapped-project")
        XCTAssertEqual(gotGraph.targets.count, 1)
        XCTAssertEqual(gotGraph.targets.values.flatMap(\.values).first?.name, "mapped-app")
        XCTAssertEqual(gotSideEffects, [sideEffect])
    }
}
