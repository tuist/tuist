import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistCore
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class XcodeBuildControllerIntegrationTests: TuistTestCase {
    var subject: XcodeBuildController!
    var formatter: MockFormatter!

    override func setUp() {
        super.setUp()
        formatter = MockFormatter()
        subject = XcodeBuildController(formatter: formatter)
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
        formatter = nil
    }

    func test_showBuildSettings() throws {
        // Given
        let target = XcodeBuildTarget.project(fixturePath(path: RelativePath("Frameworks/Frameworks.xcodeproj")))

        // When
        let got = try subject.showBuildSettings(target, scheme: "iOS", configuration: "Debug")
            .toBlocking()
            .single()

        // Then
        XCTAssertEqual(got.count, 1)
        let buildSettings = try XCTUnwrap(got["iOS"])
        XCTAssertEqual(buildSettings.productName, "iOS")
    }
}
