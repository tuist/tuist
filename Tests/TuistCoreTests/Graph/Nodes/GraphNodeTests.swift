import Foundation
import TSCBasic
import TuistCoreTesting
import TuistSupportTesting
import XCTest
@testable import TuistCore

final class GraphNodeTests: XCTestCase {
    func test_set() {
        // Given
        let a = GraphNode(path: "/path/a", name: "a")
        let b = GraphNode(path: "/path/b", name: "b")
        let c1 = TargetNode(
            project: .test(path: "/path/c"),
            target: .test(name: "c1"),
            dependencies: []
        )
        let c2 = TargetNode(
            project: .test(path: "/path/c"),
            target: .test(name: "c2"),
            dependencies: []
        )
        let d = LibraryNode(path: "/path/a", publicHeaders: "/path/to/headers", architectures: [.arm64], linking: .static)
        let e = LibraryNode(path: "/path/c", publicHeaders: "/path/to/headers", architectures: [.arm64], linking: .static)

        // When
        var set = Set<GraphNode>()
        set.insert(a)
        set.insert(b)
        set.insert(c1)
        set.insert(c2)
        set.insert(d)
        set.insert(e)

        // Then
        XCTAssertEqual(set.count, 6)
    }

    func test_equality() {
        // Given
        let a1 = GraphNode(path: "/a", name: "a")
        let a2 = GraphNode(path: "/a", name: "a")
        let b = GraphNode(path: "/b", name: "b")

        // When / Then
        XCTAssertEqual(a1, a2)
        XCTAssertNotEqual(a2, b)
        XCTAssertEqual(b, b)
    }

    func test_subclass_equality() {
        // Given
        let a = GraphNode(path: "/a", name: "a")
        let b = TargetNode(project: .test(path: "/a"), target: .test(), dependencies: [])
        let c = LibraryNode(path: "/a", publicHeaders: "/path/to/headers", architectures: [.arm64], linking: .static)

        // When / Then
        let all = [a, b, c]
        XCTAssertEqual(a, a)
        XCTAssertEqual(b, b)
        XCTAssertEqual(c, c)

        for lhs in all.enumerated() {
            for rhs in all.enumerated() where lhs.offset != rhs.offset {
                XCTAssertNotEqual(lhs.element, rhs.element)
            }
        }
    }
}
