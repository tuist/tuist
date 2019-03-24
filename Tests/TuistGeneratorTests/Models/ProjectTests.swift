import Basic
import Foundation
import XCTest
@testable import TuistGenerator

final class ProjectTests: XCTestCase {
    func test_sortedTargetsForProjectScheme() {
        let framework = Target.test(name: "Framework", product: .framework)
        let app = Target.test(name: "App", product: .app)
        let appTests = Target.test(name: "AppTets", product: .unitTests)
        let frameworkTests = Target.test(name: "FrameworkTests", product: .unitTests)
        let project = Project.test(targets: [
            framework, app, appTests, frameworkTests,
        ])

        let graph = createGraph(project: project, dependencies: [
            (target: framework, dependencies: []),
            (target: frameworkTests, dependencies: [framework]),
            (target: app, dependencies: [framework]),
            (target: appTests, dependencies: [app]),
        ])

        let got = project.sortedTargetsForProjectScheme(graph: graph)
        XCTAssertEqual(got.count, 4)
        XCTAssertEqual(got[0], framework)
        XCTAssertEqual(got[1], app)
        XCTAssertEqual(got[2], appTests)
        XCTAssertEqual(got[3], frameworkTests)
    }

    // MARK: - Private

    private func createTargetNodes(project: Project,
                                   dependencies: [(target: Target, dependencies: [Target])]) -> [TargetNode] {
        let nodesCache = Dictionary(uniqueKeysWithValues: dependencies.map {
            ($0.target.name, TargetNode(project: project,
                                        target: $0.target,
                                        dependencies: []))
        })

        return dependencies.map {
            let node = nodesCache[$0.target.name]!
            node.dependencies = $0.dependencies.map { nodesCache[$0.name]! }
            return node
        }
    }

    private func createGraph(project: Project,
                             dependencies: [(target: Target, dependencies: [Target])]) -> Graph {
        let targetNodes = createTargetNodes(project: project, dependencies: dependencies)

        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)

        targetNodes.forEach { cache.add(targetNode: $0) }

        return graph
    }
}
