import XCTest
@testable import TuistSupport
@testable import TuistSupportTesting

class XcodeControllerIntegrationTests: TuistTestCase {
    var subject: XcodeController!

    override func setUp() {
        super.setUp()
        subject = XcodeController()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_selected_version_succeeds() async throws {
        // When
        let got = try await subject.selectedVersion()

        // Then
        XCTAssertNoThrow(got)
    }
}
