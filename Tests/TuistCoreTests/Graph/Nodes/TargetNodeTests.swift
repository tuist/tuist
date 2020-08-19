import Foundation
import TSCBasic
import XCTest

import TuistSupportTesting
@testable import TuistCore

final class TargetNodeTests: XCTestCase {
    func test_equality() {
        // Given
        let c1 = TargetNode(project: .test(path: AbsolutePath("/c")),
                            target: .test(name: "c"),
                            dependencies: [])
        let c2 = TargetNode(project: .test(path: AbsolutePath("/c")),
                            target: .test(name: "c"),
                            dependencies: [])
        let c3 = TargetNode(project: .test(path: AbsolutePath("/c")),
                            target: .test(name: "c3"),
                            dependencies: [])
        let d = TargetNode(project: .test(path: AbsolutePath("/d")),
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
        let c1: GraphNode = TargetNode(project: .test(path: AbsolutePath("/c")),
                                       target: .test(name: "c"),
                                       dependencies: [])
        let c2: GraphNode = TargetNode(project: .test(path: AbsolutePath("/c")),
                                       target: .test(name: "c"),
                                       dependencies: [])
        let c3: GraphNode = TargetNode(project: .test(path: AbsolutePath("/c")),
                                       target: .test(name: "c3"),
                                       dependencies: [])
        let d: GraphNode = TargetNode(project: .test(path: AbsolutePath("/d")),
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
        let cocoapods = CocoaPodsNode.test()
        let xcframework = XCFrameworkNode.test()
        let node = TargetNode(project: .test(path: AbsolutePath("/")),
                              target: .test(name: "Target"),
                              dependencies: [library, framework, cocoapods, xcframework])

        let expected = """
        {
        "type": "source",
        "path" : "\(node.path.pathString)",
        "bundle_id" : "\(node.target.bundleId)",
        "product" : "\(node.target.product.rawValue)",
        "name" : "\(node.target.name)",
        "dependencies" : [
        "\(library.name)",
        "\(framework.name)",
        "\(cocoapods.name)",
        "\(xcframework.name)"
        ],
        "platform" : "\(node.target.platform.rawValue)"
        }
        """

        // Then
        XCTAssertEncodableEqualToJson(node, expected)
    }

    func test_dependsOnXCTest() throws {
        // When
        let sdk = try SDKNode(name: "XCTest.framework",
                              platform: .iOS,
                              status: .required,
                              source: .developer)
        let subject = TargetNode.test(dependencies: [sdk])

        // Then
        XCTAssertTrue(subject.dependsOnXCTest)
    }

    func test_dependsOnXCTest_when_testBundle() {
        // When
        let target = Target.test(product: .uiTests)
        let subject = TargetNode.test(target: target)

        // Then
        XCTAssertTrue(subject.dependsOnXCTest)
    }
}
