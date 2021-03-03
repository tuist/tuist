import Foundation
import TSCBasic
import XCTest

@testable import TuistCore
@testable import TuistSupport
@testable import TuistSupportTesting

final class FrameworkNodeTests: TuistUnitTestCase {
    var subject: FrameworkNode!
    var frameworkPath: AbsolutePath!
    var dsymPath: AbsolutePath?
    var bcsymbolmapPaths: [AbsolutePath]!

    override func setUp() {
        super.setUp()
        let path = AbsolutePath.root
        frameworkPath = path.appending(component: "test.framework")
        dsymPath = path.appending(component: "test.dSYM")
        bcsymbolmapPaths = [path.appending(component: "test.bcsymbolmap")]
        subject = FrameworkNode(
            path: frameworkPath,
            dsymPath: dsymPath,
            bcsymbolmapPaths: bcsymbolmapPaths,
            linking: .dynamic
        )
    }

    override func tearDown() {
        frameworkPath = nil
        dsymPath = nil
        bcsymbolmapPaths = nil
        subject = nil
        super.tearDown()
    }

    func test_name() {
        XCTAssertEqual(subject.name, "test")
    }

    func test_binaryPath() {
        XCTAssertEqual(subject.binaryPath.pathString, "/test.framework/test")
    }

    func test_isCarthage() {
        XCTAssertFalse(subject.isCarthage)
        subject = FrameworkNode(
            path: AbsolutePath("/path/Carthage/Build/iOS/A.framework"),
            dsymPath: dsymPath,
            bcsymbolmapPaths: bcsymbolmapPaths,
            linking: .dynamic
        )
        XCTAssertTrue(subject.isCarthage)
    }

    func test_encode() {
        // Given
        System.shared = System()
        let expected = """
        {
        "path": "\(subject.path)",
        "architectures": [],
        "name": "test",
        "type": "precompiled",
        "product": "framework"
        }
        """

        // Then
        XCTAssertEncodableEqualToJson(subject, expected)
    }

    func test_product_when_static() {
        // Given
        let subject = FrameworkNode.test(linking: .static)

        // When
        let got = subject.product

        // Then
        XCTAssertEqual(got, .staticFramework)
    }

    func test_product_when_dynamic() {
        // Given
        let subject = FrameworkNode.test(linking: .dynamic)

        // When
        let got = subject.product

        // Then
        XCTAssertEqual(got, .framework)
    }
}
