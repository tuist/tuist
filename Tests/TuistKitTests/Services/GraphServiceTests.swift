import DOT
import Foundation
import GraphViz
import TSCBasic
import TuistSupport
import XcodeProj
import XCTest

@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class GraphServiceTests: TuistUnitTestCase {
    var subject: GraphService!
    var graphVizGenerator: MockGraphVizGenerator!
    var manifestLoader: MockManifestLoader!

    override func setUp() {
        super.setUp()
        graphVizGenerator = MockGraphVizGenerator()
        manifestLoader = MockManifestLoader()
        subject = GraphService(graphVizGenerator: graphVizGenerator,
                               manifestLoader: manifestLoader)
    }

    override func tearDown() {
        graphVizGenerator = nil
        manifestLoader = nil
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

        manifestLoader.manifestsAtStub = {
            if $0 == temporaryPath { return Set([.project]) }
            else { return Set([]) }
        }

        let graph = GraphViz.Graph()
        graphVizGenerator.generateProjectStub = graph

        // When
        try subject.run(format: .dot, skipTestTargets: false, skipExternalDependencies: false, path: nil)
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
