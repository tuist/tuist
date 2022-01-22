import Foundation
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
        subject = nil
        super.tearDown()
    }

    func test_showBuildSettings() async throws {
        // Given
        let target = XcodeBuildTarget.project(fixturePath(path: RelativePath("Frameworks/Frameworks.xcodeproj")))

        // When
        let got = try await subject.showBuildSettings(target, scheme: "iOS", configuration: "Debug")

        // Then
        XCTAssertEqual(got.count, 1)
        let buildSettings = try XCTUnwrap(got["iOS"])
        XCTAssertEqual(buildSettings.productName, "iOS")
    }
}
