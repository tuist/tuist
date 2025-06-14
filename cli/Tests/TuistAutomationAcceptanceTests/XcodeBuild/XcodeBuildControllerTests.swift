import Foundation
import Path
import TuistCore
import TuistSupport
import XCTest

@testable import TuistAutomation
@testable import TuistTesting

final class XcodeBuildControllerTests: TuistTestCase {
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
        let target = XcodeBuildTarget.project(fixturePath(path: try RelativePath(validating: "Frameworks/Frameworks.xcodeproj")))

        // When
        let got = try await subject.showBuildSettings(target, scheme: "iOS", configuration: "Debug", derivedDataPath: nil)

        // Then
        XCTAssertEqual(got.count, 1)
        let buildSettings = try XCTUnwrap(got["iOS"])
        XCTAssertEqual(buildSettings.productName, "iOS")
    }

    func test_version() async throws {
        // When
        let version = try await subject.version()

        // Then
        XCTAssertNotNil(version)
    }
}
