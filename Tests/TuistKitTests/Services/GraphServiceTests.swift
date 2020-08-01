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

    func test_run_when_graphvizIsInstalled() throws {
        // Given
        let graph = try givenGraph()
        system.succeedCommand(["brew", "list"], output: "graphviz")
        
        // When
        try subject.run(skipTestTargets: false, skipExternalDependencies: false)

        // Then
        XCTAssertEqual(try FileHandler.shared.readTextFile(graph.path), graph.dotGraph)
        XCTAssertPrinterOutputContains("""
        Deleting existing graph at \(graph.path.pathString)
        Graph exported to \(graph.path.pathString)
        """)
    }
    
    func test_run_when_graphvizIsMissing_will_install_graphviz() throws {
         // Given
         let graph = try givenGraph()
         system.succeedCommand(["brew", "list"], output: "")
         system.succeedCommand(["brew", "install", "graphviz"], output: "home")
        
         // When
         try subject.run(skipTestTargets: false, skipExternalDependencies: false)

         // Then
         XCTAssertEqual(try FileHandler.shared.readTextFile(graph.path), graph.dotGraph)
         XCTAssertPrinterOutputContains("Installing graphviz...")
         XCTAssertPrinterOutputContains("""
         Deleting existing graph at \(graph.path.pathString)
         Graph exported to \(graph.path.pathString)
         """)
     }
    
    private func givenGraph() throws -> (dotGraph: String, path: AbsolutePath) {
        let temporaryPath = try self.temporaryPath()
        let graphPath = temporaryPath.appending(component: "graph.png")
        let projectManifestPath = temporaryPath.appending(component: "Project.swift")

        try FileHandler.shared.touch(graphPath)
        try FileHandler.shared.touch(projectManifestPath)

        manifestLoader.manifestsAtStub = {
            if $0 == temporaryPath { return Set([.project]) }
            else { return Set([]) }
        }

        let graph = "graph {}"
        dotGraphGenerator.generateProjectStub = graph
        return (graph, graphPath)
    }

}
