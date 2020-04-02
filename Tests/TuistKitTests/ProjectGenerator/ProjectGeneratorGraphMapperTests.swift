import Basic
import Foundation
import TuistCore
import TuistCoreTesting
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class AnyProjectGeneratorGraphMapperTests: TuistUnitTestCase {
    func test_map() throws {
        // Given
        let input = Graph.test(name: "input")
        let output = Graph.test(name: "output")
        let subject = AnyProjectGeneratorGraphMapper(mapper: { graph in
            XCTAssertEqual(graph.name, input.name)
            return output
        })

        // When
        let got = try subject.map(graph: input)

        // Then
        XCTAssertEqual(got.name, output.name)
    }
}

final class ProjectGeneratorSequentialGraphMapperTests: TuistUnitTestCase {
    func test_map() throws {
        // Given
        let input = Graph.test(name: "0")
        let first = AnyProjectGeneratorGraphMapper(mapper: { graph in
            XCTAssertEqual(graph.name, "0")
            return Graph.test(name: "1")
        })
        let second = AnyProjectGeneratorGraphMapper(mapper: { graph in
            XCTAssertEqual(graph.name, "1")
            return Graph.test(name: "2")
        })
        let subject = ProjectGeneratorSequentialGraphMapper([first, second])

        // When
        let got = try subject.map(graph: input)

        // Then
        XCTAssertEqual(got.name, "2")
    }
}
