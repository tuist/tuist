import Foundation
import TuistSupportTesting
import XCTest

@testable import TuistServer

final class FullHandleServiceTests: TuistUnitTestCase {
    private var subject: FullHandleServicing!
    override func setUp() {
        super.setUp()

        subject = FullHandleService()
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }

    func test_parsing_full_handle_when_valid() throws {
        // When
        let got = try subject.parse("tuist-org/tuist")

        // Then
        XCTAssertEqual(got.accountHandle, "tuist-org")
        XCTAssertEqual(got.projectHandle, "tuist")
    }

    func test_parsing_full_handle_when_only_account_or_project_handle_is_present() throws {
        // When / Then
        XCTAssertThrowsSpecific(
            try subject.parse("tuist"),
            FullHandleServiceError.invalidHandle("tuist")
        )
    }

    func test_parsing_full_handle_when_extra_components_are_present() throws {
        // When / Then
        XCTAssertThrowsSpecific(
            try subject.parse("tuist-org/tuist/extra"),
            FullHandleServiceError.invalidHandle("tuist-org/tuist/extra")
        )
    }
}
