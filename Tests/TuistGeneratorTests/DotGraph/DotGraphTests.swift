import Foundation
import XCTest

@testable import TuistGenerator

final class DotGraphTests: XCTestCase {
    func test_description() {
        // Given
        let nodes = Set([DotGraphNode(name: "App",
                                      attributes: Set([.label("App")])),
                         DotGraphNode(name: "Search",
                                      attributes: Set([.label("Search"), .shape(.circle)])),
                         DotGraphNode(name: "Core",
                                      attributes: Set([.label("Core")]))])
        let dependencies = Set([DotGraphDependency(from: "App", to: "Search"),
                                DotGraphDependency(from: "Search", to: "Core")])
        let subject = DotGraph(name: "TestGraph",
                               type: .directed,
                               nodes: nodes,
                               dependencies: dependencies)

        // When
        let got = subject.description

        // Then
        let expected = """
        digraph "TestGraph" {
          App [label="App"]
          Core [label="Core"]
          Search [label="Search", shape="circle"]

          App -> Search
          Search -> Core
        }
        """
        XCTAssertEqual(got, expected)
    }
}
