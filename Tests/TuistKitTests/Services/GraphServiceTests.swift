import DOT
import Foundation
import GraphViz
import TSCBasic
import TuistPlugin
import TuistSupport
import XcodeProj
import XCTest

@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class GraphServiceTests: TuistUnitTestCase {
    var simpleGraphLoader: MockSimpleGraphLoader!
    var graphVizMapper: MockGraphToGraphVizMapper!
    var subject: GraphService!

    override func setUp() {
        super.setUp()
        graphVizMapper = MockGraphToGraphVizMapper()
        simpleGraphLoader = MockSimpleGraphLoader()

        subject = GraphService(
            graphVizGenerator: graphVizMapper,
            simpleGraphLoader: simpleGraphLoader
        )
    }

    override func tearDown() {
        graphVizMapper = nil
        simpleGraphLoader = nil
        subject = nil
        super.tearDown()
    }

    func test_run_whenDot() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let graphPath = temporaryPath.appending(component: "graph.dot")
        let projectManifestPath = temporaryPath.appending(component: "Project.swift")

        try FileHandler.shared.touch(graphPath)
        try FileHandler.shared.touch(projectManifestPath)
        graphVizMapper.stubMap = Graph()

        // When
        try subject.run(
            format: .dot,
            layoutAlgorithm: .dot,
            skipTestTargets: false,
            skipExternalDependencies: false,
            targetsToFilter: [],
            path: temporaryPath,
            outputPath: temporaryPath
        )
        let got = try FileHandler.shared.readTextFile(graphPath)
        let expected = "graph { }"
        // Then
        XCTAssertEqual(got, expected)
        XCTAssertPrinterOutputContains("""
        Deleting existing graph at \(graphPath.pathString)
        Graph exported to \(graphPath.pathString)
        """)
    }
}
