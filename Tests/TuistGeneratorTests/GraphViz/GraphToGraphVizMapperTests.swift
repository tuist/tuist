import Foundation
import GraphViz
import Path
import TuistCore
import XcodeGraph
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
                targetsToFilter: []
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
                targetsToFilter: []
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
                targetsToFilter: []
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
                targetsToFilter: []
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
                targetsToFilter: ["Tuist iOS"]
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
        onlyiOS: Bool = false
    ) -> GraphViz.Graph {
        var graph = GraphViz.Graph(directed: true, strict: false)

        let tuist = GraphViz.Node("Tuist iOS")
        let coreData = GraphViz.Node("CoreData")
        let rxSwift = GraphViz.Node("RxSwift")
        let xcodeProj = GraphViz.Node("XcodeProj")
        let core = GraphViz.Node("Core")
        let coreTests = GraphViz.Node("CoreTests")
        let watchOS = GraphViz.Node("Tuist watchOS")
        let externalDependency = GraphViz.Node("External dependency")

        graph.append(contentsOf: [tuist, core])
        if !onlyiOS {
            graph.append(watchOS)
        }
        graph.append(GraphViz.Edge(from: tuist, to: core))
        if !onlyiOS {
            graph.append(GraphViz.Edge(from: watchOS, to: core))
        }

        if includeExternalDependencies {
            graph.append(
                contentsOf: [
                    coreData, rxSwift, xcodeProj, externalDependency,
                ]
            )
            graph.append(contentsOf: [
                GraphViz.Edge(from: core, to: xcodeProj),
                GraphViz.Edge(from: core, to: rxSwift),
                GraphViz.Edge(from: core, to: coreData),
                GraphViz.Edge(from: core, to: externalDependency),
            ])
        }

        if includeTests {
            graph.append(coreTests)
            graph.append(
                GraphViz.Edge(from: coreTests, to: core)
            )
        }

        return graph
    }

    private func makeGivenGraph() throws -> XcodeGraph.Graph {
        let framework = GraphDependency.testFramework(path: try AbsolutePath(validating: "/XcodeProj.framework"))
        let library = GraphDependency.testLibrary(path: try AbsolutePath(validating: "/RxSwift.a"))
        let sdk = GraphDependency.testSDK(name: "CoreData.framework", status: .required, source: .developer)
        let projectPath: AbsolutePath = "/"
        let coreProjectPath: AbsolutePath = "/Core"
        let externalProjectPath: AbsolutePath = "/Tuist/Dependencies"
        let coreTarget = Target.test(name: "Core")
        let core = GraphTarget.test(
            path: coreProjectPath,
            target: coreTarget
        )
        let coreDependency = GraphDependency.target(name: core.target.name, path: core.path)
        let coreTestsTarget = Target.test(
            name: "CoreTests",
            product: .unitTests
        )
        let coreTests = GraphTarget.test(
            path: coreProjectPath,
            target: coreTestsTarget
        )
        let iOSAppTarget = Target.test(name: "Tuist iOS")
        let iOSApp = GraphTarget.test(target: iOSAppTarget)
        let watchAppTarget = Target.test(
            name: "Tuist watchOS",
            platform: .watchOS,
            deploymentTarget: .watchOS("6")
        )
        let watchApp = GraphTarget.test(target: watchAppTarget)

        let externalTargetTarget = Target.test(name: "External dependency")
        let externalTarget = GraphTarget.test(path: externalProjectPath, target: externalTargetTarget)
        let project = Project.test(path: projectPath, targets: [iOSAppTarget, watchAppTarget])
        let coreProject = Project.test(path: coreProjectPath, targets: [coreTarget, coreTestsTarget])
        let externalProject = Project.test(path: "/Tuist/Dependencies", targets: [externalTargetTarget], isExternal: true)
        let externalDependency = GraphDependency.target(name: externalTarget.target.name, path: externalTarget.path)

        let graph = XcodeGraph.Graph.test(
            projects: [
                project.path: project,
                coreProject.path: coreProject,
                externalProject.path: externalProject,
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
