import Basic
import Foundation
import SPMUtility
import TuistSupport
import XcodeProj
import XCTest
@testable import TuistSupportTesting
@testable import TuistKit

final class GraphCommandTests: TuistUnitTestCase {
    var subject: GraphCommand!
    var dotGraphGenerator: MockDotGraphGenerator!
    var manifestLoader: MockGraphManifestLoader!
    var parser: ArgumentParser!

    override func setUp() {
        super.setUp()
        dotGraphGenerator = MockDotGraphGenerator()
        manifestLoader = MockGraphManifestLoader()
        parser = ArgumentParser.test()
        subject = GraphCommand(parser: parser,
                               dotGraphGenerator: dotGraphGenerator,
                               manifestLoader: manifestLoader)
    }

    override func tearDown() {
        dotGraphGenerator = nil
        manifestLoader = nil
        parser = nil
        subject = nil
        super.tearDown()
    }

    func test_command() {
        XCTAssertEqual(GraphCommand.command, "graph")
    }

    func test_overview() {
        XCTAssertEqual(GraphCommand.overview, "Generates a dot graph from the workspace or project in the current directory.")
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
        let result = try parser.parse([GraphCommand.command])
        try subject.run(with: result)

        // Then
        XCTAssertEqual(try FileHandler.shared.readTextFile(graphPath), graph)
        XCTAssertPrinterOutputContains("""
        Deleting existing graph at \(graphPath.pathString)
        Graph exported to \(graphPath.pathString)
        """)
    }
}
