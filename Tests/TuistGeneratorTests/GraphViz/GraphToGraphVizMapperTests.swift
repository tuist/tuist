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
        subject = nil
        super.tearDown()
    }

    func test_map() throws {
        // Given
        let graph = try makeGivenGraph()

        // When
        let got = subject.map(
            graph: graph,
            targetsAndDependencies: graph.filter(
                skipTestTargets: false,
                skipExternalDependencies: false,
                platformToFilter: nil,
                targetsToFilter: [],
                excludeTargetsContaining: []
            )
        )
        let expected = makeExpectedGraphViz()
        let gotNodeIds = got.nodes.map(\.id).sorted()
        let expectedNodeIds = expected.nodes.map(\.id).sorted()
        let gotEdgeIds = got.edges.map { $0.from + " -> " + $0.to }.sorted()
        let expectedEdgeIds = expected.edges.map { $0.from + " -> " + $0.to }.sorted()
        XCTAssertEqual(gotNodeIds, expectedNodeIds)
        XCTAssertEqual(gotEdgeIds, expectedEdgeIds)
    }
    
    func test_map_excluding_targets_containing_strings() throws {
        // Given
        let graph = try makeGivenGraph()
        let excludeTargetsContaining = ["External", "rx"]
        
        // When
        let got = subject.map(
            graph: graph,
            targetsAndDependencies: graph.filter(
                skipTestTargets: false,
                skipExternalDependencies: false,
                platformToFilter: nil,
                targetsToFilter: [],
                excludeTargetsContaining: excludeTargetsContaining
            )
        )
        
        // Then
        let expected = makeExpectedGraphViz(excludeTargetsContaining: excludeTargetsContaining)
        let gotNodeIds = got.nodes.map(\.id).sorted()
        let expectedNodeIds = expected.nodes.map(\.id).sorted()
        let gotEdgeIds = got.edges.map { "\($0.from) -> \($0.to)" }.sorted()
        let expectedEdgeIds = expected.edges.map { "\($0.from) -> \($0.to)" }.sorted()
        
        XCTAssertEqual(gotNodeIds, expectedNodeIds)
        XCTAssertEqual(gotEdgeIds, expectedEdgeIds)
    }
    
    func test_map_skipping_external_dependencies() throws {
        // Given
        let graph = try makeGivenGraph()

        // When
        let got = subject.map(
            graph: graph,
            targetsAndDependencies: graph.filter(
                skipTestTargets: false,
                skipExternalDependencies: true,
                platformToFilter: nil,
                targetsToFilter: [],
                excludeTargetsContaining: []
            )
        )
        let expected = makeExpectedGraphViz(includeExternalDependencies: false)
        let gotNodeIds = got.nodes.map(\.id).sorted()
        let expectedNodeIds = expected.nodes.map(\.id).sorted()
        let gotEdgeIds = got.edges.map { $0.from + " -> " + $0.to }.sorted()
        let expectedEdgeIds = expected.edges.map { $0.from + " -> " + $0.to }.sorted()

        XCTAssertEqual(gotNodeIds, expectedNodeIds)
        XCTAssertEqual(gotEdgeIds, expectedEdgeIds)
    }

    func test_map_skipping_tests() throws {
        // Given
        let graph = try makeGivenGraph()

        // When
        let got = subject.map(
            graph: graph,
            targetsAndDependencies: graph.filter(
                skipTestTargets: true,
                skipExternalDependencies: false,
                platformToFilter: nil,
                targetsToFilter: [],
                excludeTargetsContaining: []
            )
        )
        let expected = makeExpectedGraphViz(includeTests: false)
        let gotNodeIds = got.nodes.map(\.id).sorted()
        let expectedNodeIds = expected.nodes.map(\.id).sorted()
        let gotEdgeIds = got.edges.map { $0.from + " -> " + $0.to }.sorted()
        let expectedEdgeIds = expected.edges.map { $0.from + " -> " + $0.to }.sorted()

        XCTAssertEqual(gotNodeIds, expectedNodeIds)
        XCTAssertEqual(gotEdgeIds, expectedEdgeIds)
    }

    func test_map_filter_platform() throws {
        // Given
        let graph = try makeGivenGraph()

        // When
        let got = subject.map(
            graph: graph,
            targetsAndDependencies: graph.filter(
                skipTestTargets: false,
                skipExternalDependencies: false,
                platformToFilter: .iOS,
                targetsToFilter: [],
                excludeTargetsContaining: []
            )
        )
        let expected = makeExpectedGraphViz(onlyiOS: true)
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
        var expected = GraphViz.Graph(directed: true, strict: false)
        let tuist = GraphViz.Node("Tuist iOS")
        let core = GraphViz.Node("Core")
        expected.append(contentsOf: [tuist, core])
        expected.append(GraphViz.Edge(from: tuist, to: core))

        // When
        let got = subject.map(
            graph: graph,
            targetsAndDependencies: graph.filter(
                skipTestTargets: false,
                skipExternalDependencies: true,
                platformToFilter: nil,
                targetsToFilter: ["Tuist iOS"],
                excludeTargetsContaining: []
            )
        )

        // Then
        let gotNodeIds = got.nodes.map(\.id).sorted()
        let expectedNodeIds = expected.nodes.map(\.id).sorted()
        let gotEdgeIds = got.edges.map { $0.from + " -> " + $0.to }.sorted()
        let expectedEdgeIds = expected.edges.map { $0.from + " -> " + $0.to }.sorted()
        
        XCTAssertEqual(gotNodeIds, expectedNodeIds)
        XCTAssertEqual(gotEdgeIds, expectedEdgeIds)
    }

    private func makeExpectedGraphViz(
        includeExternalDependencies: Bool = true,
        includeTests: Bool = true,
        onlyiOS: Bool = false,
        excludeTargetsContaining: [String] = []
    ) -> GraphViz.Graph {
        var nodes = [GraphViz.Node]()
        var edges = [GraphViz.Edge]()

        let tuist = GraphViz.Node("Tuist iOS")
        let coreData = GraphViz.Node("CoreData")
        let rxSwift = GraphViz.Node("RxSwift")
        let xcodeProj = GraphViz.Node("XcodeProj")
        let core = GraphViz.Node("Core")
        let coreTests = GraphViz.Node("CoreTests")
        let watchOS = GraphViz.Node("Tuist watchOS")
        let externalDependency = GraphViz.Node("External dependency")

        nodes.append(contentsOf: [tuist, core])
        if !onlyiOS {
            nodes.append(watchOS)
        }

        edges.append(GraphViz.Edge(from: tuist, to: core))
        if !onlyiOS {
            edges.append(GraphViz.Edge(from: watchOS, to: core))
        }

        if includeExternalDependencies {
            nodes.append(contentsOf: [coreData, rxSwift, xcodeProj, externalDependency])
            edges.append(contentsOf: [
                GraphViz.Edge(from: core, to: xcodeProj),
                GraphViz.Edge(from: core, to: rxSwift),
                GraphViz.Edge(from: core, to: coreData),
                GraphViz.Edge(from: core, to: externalDependency),
            ])
        }

        if includeTests {
            nodes.append(coreTests)
            edges.append(GraphViz.Edge(from: coreTests, to: core))
        }

        nodes = nodes.filter { node in
            !excludeTargetsContaining.contains(where: { node.id.lowercased().contains($0.lowercased()) })
        }
        edges = edges.filter { edge in
            !(excludeTargetsContaining.contains(where: { edge.from.lowercased().contains($0.lowercased()) }) || excludeTargetsContaining.contains(where: { edge.to.lowercased().contains($0.lowercased()) }))
        }

        var graph = GraphViz.Graph(directed: true)
        graph.append(contentsOf: nodes)
        for edge in edges {
            graph.append(edge)
        }
        
        return graph
    }

    private func makeGivenGraph() throws -> TuistGraph.Graph {
        let project = Project.test(path: "/")
        let coreProject = Project.test(path: "/Core")
        let externalProject = Project.test(path: "/Tuist/Dependencies", isExternal: true)
        let framework = GraphDependency.testFramework(path: try AbsolutePath(validating: "/XcodeProj.framework"))
        let library = GraphDependency.testLibrary(path: try AbsolutePath(validating: "/RxSwift.a"))
        let sdk = GraphDependency.testSDK(name: "CoreData.framework", status: .required, source: .developer)

        let core = GraphTarget.test(
            path: coreProject.path,
            target: Target.test(name: "Core")
        )
        let coreDependency = GraphDependency.target(name: core.target.name, path: core.path)
        let coreTests = GraphTarget.test(
            path: coreProject.path,
            target: Target.test(
                name: "CoreTests",
                product: .unitTests
            )
        )

        let iOSApp = GraphTarget.test(target: Target.test(name: "Tuist iOS"))
        let watchApp = GraphTarget.test(target: Target.test(
            name: "Tuist watchOS",
            platform: .watchOS,
            deploymentTarget: .watchOS("6")
        ))

        let externalTarget = GraphTarget.test(path: externalProject.path, target: Target.test(name: "External dependency"))
        let externalDependency = GraphDependency.target(name: externalTarget.target.name, path: externalTarget.path)

        let graph = TuistGraph.Graph.test(
            projects: [
                project.path: project,
                coreProject.path: coreProject,
                externalProject.path: externalProject,
            ],
            targets: [
                project.path: [
                    iOSApp.target.name: iOSApp.target,
                    watchApp.target.name: watchApp.target,
                ],
                coreProject.path: [
                    core.target.name: core.target,
                    coreTests.target.name: coreTests.target,
                ],
                externalProject.path: [
                    externalTarget.target.name: externalTarget.target,
                ],
            ],
            dependencies: [
                .target(name: core.target.name, path: core.path): [
                    framework,
                    library,
                    sdk,
                    externalDependency,
                ],
                .target(name: coreTests.target.name, path: coreTests.path): [coreDependency],
                .target(name: iOSApp.target.name, path: iOSApp.path): [coreDependency],
                .target(name: watchApp.target.name, path: watchApp.path): [coreDependency],
            ]
        )

        return graph
    }
}
