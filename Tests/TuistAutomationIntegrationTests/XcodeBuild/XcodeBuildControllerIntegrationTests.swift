import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistAutomation
@testable import TuistSupportTesting

final class XcodeBuildControllerIntegrationTests: TuistTestCase {
    var subject: XcodeBuildController!

    override func setUp() {
        super.setUp()
        subject = XcodeBuildController()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
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
