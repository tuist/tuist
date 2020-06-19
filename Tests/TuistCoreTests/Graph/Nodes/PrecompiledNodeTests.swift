import Foundation
import TSCBasic
import XCTest

import TuistSupportTesting
@testable import TuistCore

final class PrecompiledNodeTests: XCTestCase {
    var system: MockSystem!

    override func setUp() {
        super.setUp()
        system = MockSystem()
    }

    func test_name() {
        // Given
        let subject = PrecompiledNode(path: AbsolutePath("/Alamofire.framework"))

        // When
        let got = subject.name

        // Then
        XCTAssertEqual(got, "Alamofire")
    }

    func test_is_dynamic_and_linkable_when_xcframework() {
        // Given
        let subject = XCFrameworkNode.test()

        // When
        let got = subject.isDynamicAndLinkable()

        // Then
        XCTAssertTrue(got)
    }

    func test_is_dynamic_and_linkable_when_dynamic_framework() {
        // Given
        let subject = FrameworkNode.test(linking: .dynamic)

        // When
        let got = subject.isDynamicAndLinkable()

        // Then
        XCTAssertTrue(got)
    }

    func test_is_dynamic_and_linkable_when_static_framework() {
        // Given
        let subject = FrameworkNode.test(linking: .static)

        // When
        let got = subject.isDynamicAndLinkable()

        // Then
        XCTAssertFalse(got)
    }
}
