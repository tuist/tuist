import Foundation
import TSCBasic
import TuistSupport
import XcodeProj
import XCTest

@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class GraphServiceTests: TuistUnitTestCase {
    var subject: GraphService!
    var dotGraphGenerator: MockDotGraphGenerator!
    var manifestLoader: MockManifestLoader!

    override func setUp() {
        super.setUp()
        dotGraphGenerator = MockDotGraphGenerator()
        manifestLoader = MockManifestLoader()
        subject = GraphService(dotGraphGenerator: dotGraphGenerator,
                               manifestLoader: manifestLoader)
    }

    override func tearDown() {
        dotGraphGenerator = nil
        manifestLoader = nil
        subject = nil
        super.tearDown()
    }

    func test_run() throws {
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

        let graph = "graph {}"
        dotGraphGenerator.generateProjectStub = graph

        // When
        try subject.run(skipTestTargets: false, skipExternalDependencies: false)

        // Then
        XCTAssertEqual(try FileHandler.shared.readTextFile(graphPath), graph)
        XCTAssertPrinterOutputContains("""
        Deleting existing graph at \(graphPath.pathString)
        Graph exported to \(graphPath.pathString)
        """)
    }
}
