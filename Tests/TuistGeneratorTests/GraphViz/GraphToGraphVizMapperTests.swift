import Foundation
import GraphViz
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class GraphToGraphVizMapperTests: XCTestCase {
    var subject: GraphToGraphVizMapper!

    override func setUp() {
        super.setUp()
        subject = GraphToGraphVizMapper()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_map() throws {
        // Given
        let graph = try makeGivenGraph()

        // When
        let got = subject.map(graph: graph, skipTestTargets: false, skipExternalDependencies: false, targetsToFilter: [])
        let expected = makeExpectedGraphViz()
        let gotNodeIds = got.nodes.map(\.id).sorted()
        let expectedNodeIds = expected.nodes.map(\.id).sorted()
        let gotEdgeIds = got.edges.map { $0.from + " -> " + $0.to }.sorted()
        let expectedEdgeIds = expected.edges.map { $0.from + " -> " + $0.to }.sorted()
        XCTAssertEqual(gotNodeIds, expectedNodeIds)
        XCTAssertEqual(gotEdgeIds, expectedEdgeIds)
    }

    func test_map_skipping_external_dependencies() throws {
        // Given
        let graph = try makeGivenGraph()

        // When
        let got = subject.map(graph: graph, skipTestTargets: false, skipExternalDependencies: true, targetsToFilter: [])
        let expected = makeExpectedGraphViz(includeExternalDependencies: false)
        let gotNodeIds = got.nodes.map(\.id).sorted()
        let expectedNodeIds = expected.nodes.map(\.id).sorted()
        let gotEdgeIds = got.edges.map { $0.from + " -> " + $0.to }.sorted()
        let expectedEdgeIds = expected.edges.map { $0.from + " -> " + $0.to }.sorted()

        XCTAssertEqual(gotNodeIds, expectedNodeIds)
        XCTAssertEqual(gotEdgeIds, expectedEdgeIds)
    }

    func test_map_filter_targets() throws {
        // Given
        let graph = try makeGivenGraph()

        // When
        let got = subject.map(graph: graph, skipTestTargets: false, skipExternalDependencies: true, targetsToFilter: ["Tuist iOS"])
        let expected = makeExpectedGraphViz(includeExternalDependencies: false, onlyiOS: true)
        let gotNodeIds = got.nodes.map(\.id).sorted()
        let expectedNodeIds = expected.nodes.map(\.id).sorted()
        let gotEdgeIds = got.edges.map { $0.from + " -> " + $0.to }.sorted()
        let expectedEdgeIds = expected.edges.map { $0.from + " -> " + $0.to }.sorted()

        XCTAssertEqual(gotNodeIds, expectedNodeIds)
        XCTAssertEqual(gotEdgeIds, expectedEdgeIds)
    }

    private func makeExpectedGraphViz(includeExternalDependencies: Bool = true, onlyiOS: Bool = false) -> GraphViz.Graph {
        var graph = GraphViz.Graph(directed: true, strict: false)

        let tuist = GraphViz.Node("Tuist iOS")
        let coreData = GraphViz.Node("CoreData")
        let rxSwift = GraphViz.Node("RxSwift")
        let xcodeProj = GraphViz.Node("XcodeProj")
        let core = GraphViz.Node("Core")
        let watchOS = GraphViz.Node("Tuist watchOS")

        graph.append(contentsOf: [tuist, coreData, rxSwift, xcodeProj, core])
        if !onlyiOS {
            graph.append(watchOS)
        }
        graph.append(GraphViz.Edge(from: tuist, to: core))
        if !onlyiOS {
            graph.append(GraphViz.Edge(from: watchOS, to: core))
        }

        if includeExternalDependencies {
            graph.append(contentsOf: [
                GraphViz.Edge(from: core, to: xcodeProj),
                GraphViz.Edge(from: core, to: rxSwift),
                GraphViz.Edge(from: core, to: coreData),
            ])
        }
        return graph
    }

    private func makeGivenGraph() throws -> TuistCore.Graph {
        let project = Project.test()
        let framework = FrameworkNode.test(path: AbsolutePath("/XcodeProj.framework"))
        let library = LibraryNode.test(path: AbsolutePath("/RxSwift.a"))
        let sdk = try SDKNode(name: "CoreData.framework", platform: .iOS, status: .required, source: .developer)

        let core = TargetNode.test(target: Target.test(name: "Core"), dependencies: [
            framework, library, sdk,
        ])
        let iOSApp = TargetNode.test(target: Target.test(name: "Tuist iOS"), dependencies: [core])
        let watchApp = TargetNode.test(target: Target.test(name: "Tuist watchOS"), dependencies: [core])

        let graph = Graph.test(entryNodes: [iOSApp, watchApp],
                               projects: [project],
                               precompiled: [framework, library],
                               targets: [project.path: [core, iOSApp, watchApp]])

        return graph
    }
}
