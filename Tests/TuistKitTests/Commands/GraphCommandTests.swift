import Basic
import Foundation
import SPMUtility
import TuistCore
import XcodeProj
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

final class GraphCommandTests: XCTestCase {
    var subject: GraphCommand!
    var dotGraphGenerator: MockDotGraphGenerator!
    var fileHandler: MockFileHandler!
    var manifestLoader: MockGraphManifestLoader!
    var parser: ArgumentParser!

    override func setUp() {
        super.setUp()
        mockEnvironment()
        fileHandler = sharedMockFileHandler()

        dotGraphGenerator = MockDotGraphGenerator()
        manifestLoader = MockGraphManifestLoader()
        parser = ArgumentParser.test()
        subject = GraphCommand(parser: parser,
                               dotGraphGenerator: dotGraphGenerator,
                               manifestLoader: manifestLoader)
    }

    func test_command() {
        XCTAssertEqual(GraphCommand.command, "graph")
    }

    func test_overview() {
        XCTAssertEqual(GraphCommand.overview, "Generates a dot graph from the workspace or project in the current directory.")
    }

    func test_run() throws {
        // Given
        let graphPath = fileHandler.currentPath.appending(component: "graph.dot")
        let projectManifestPath = fileHandler.currentPath.appending(component: "Project.swift")

        try fileHandler.touch(graphPath)
        try fileHandler.touch(projectManifestPath)

        manifestLoader.manifestsAtStub = {
            if $0 == self.fileHandler.currentPath { return Set([.project]) }
            else { return Set([]) }
        }

        let graph = "graph {}"
        dotGraphGenerator.generateProjectStub = graph

        // When
        let result = try parser.parse([GraphCommand.command])
        try subject.run(with: result)

        // Then
        XCTAssertEqual(try fileHandler.readTextFile(graphPath), graph)
        XCTAssertPrinterOutputContains("""
        Deleting existing graph at \(graphPath.pathString)
        Graph exported to \(graphPath.pathString)
        """)
    }
}
