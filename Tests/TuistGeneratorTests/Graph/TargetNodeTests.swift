import Basic
import Foundation
import XCTest

import TuistCoreTesting
@testable import TuistGenerator

final class TargetNodeTests: XCTestCase {
    func test_equality() {
        // Given
        let c1 = TargetNode(project: .test(path: "/c"),
                            target: .test(name: "c"),
                            dependencies: [])
        let c2 = TargetNode(project: .test(path: "/c"),
                            target: .test(name: "c"),
                            dependencies: [])
        let c3 = TargetNode(project: .test(path: "/c"),
                            target: .test(name: "c3"),
                            dependencies: [])
        let d = TargetNode(project: .test(path: "/d"),
                           target: .test(name: "c"),
                           dependencies: [])

        // When / Then
        XCTAssertEqual(c1, c2)
        XCTAssertNotEqual(c2, c3)
        XCTAssertNotEqual(c1, d)
        XCTAssertEqual(d, d)
    }

    func test_equality_asGraphNodes() {
        // Given
        let c1: GraphNode = TargetNode(project: .test(path: "/c"),
                                       target: .test(name: "c"),
                                       dependencies: [])
        let c2: GraphNode = TargetNode(project: .test(path: "/c"),
                                       target: .test(name: "c"),
                                       dependencies: [])
        let c3: GraphNode = TargetNode(project: .test(path: "/c"),
                                       target: .test(name: "c3"),
                                       dependencies: [])
        let d: GraphNode = TargetNode(project: .test(path: "/d"),
                                      target: .test(name: "c"),
                                      dependencies: [])

        // When / Then
        XCTAssertEqual(c1, c2)
        XCTAssertNotEqual(c2, c3)
        XCTAssertNotEqual(c1, d)
    }

    func test_encode() {
        // Given
        let library = LibraryNode.test()
        let framework = FrameworkNode.test()
        let node = TargetNode(project: .test(path: "/"),
                              target: .test(name: "Target"),
                              dependencies: [library, framework])

        let expected = """
        {
        "type": "source",
        "path" : "\(node.path.pathString)",
        "bundle_id" : "\(node.target.bundleId)",
        "product" : "\(node.target.product.rawValue)",
        "name" : "\(node.target.name)",
        "dependencies" : [
        "\(library.name)",
        "\(framework.name)"
        ],
        "platform" : "\(node.target.platform.rawValue)"
        }
        """

        // Then
        XCTAssertEncodableEqualToJson(node, expected)
    }
}
