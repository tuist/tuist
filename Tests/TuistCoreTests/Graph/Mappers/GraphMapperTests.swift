import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import XCTest
@testable import TuistSupportTesting

final class AnyGraphMapperTests: TuistUnitTestCase {
    func test_map() throws {
        // Given
        let input = ValueGraph.test(name: "input")
        let output = ValueGraph.test(name: "output")
        let subject = AnyGraphMapper(mapper: { graph in
            XCTAssertEqual(graph.name, input.name)
            return (output, [])
        })

        // When
        let (got, _) = try subject.map(graph: input)

        // Then
        XCTAssertEqual(got.name, output.name)
    }
}

final class SequentialGraphMapperTests: TuistUnitTestCase {
    func test_map() throws {
        // Given
        let firstSideEffect = SideEffectDescriptor.file(.init(path: "/first"))
        let input = ValueGraph.test(name: "0")
        let first = AnyGraphMapper(mapper: { graph in
            XCTAssertEqual(graph.name, "0")
            return (ValueGraph.test(name: "1"), [firstSideEffect])
        })
        let secondSideEffect = SideEffectDescriptor.file(.init(path: "/second"))
        let second = AnyGraphMapper(mapper: { graph in
            XCTAssertEqual(graph.name, "1")
            return (ValueGraph.test(name: "2"), [secondSideEffect])
        })
        let subject = SequentialGraphMapper([first, second])

        // When
        let (got, sideEffects) = try subject.map(graph: input)

        // Then
        XCTAssertEqual(got.name, "2")
        XCTAssertEqual(sideEffects, [firstSideEffect, secondSideEffect])
    }
}
