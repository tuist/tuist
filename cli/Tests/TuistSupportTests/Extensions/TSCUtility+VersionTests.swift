import TSCUtility
import XCTest
@testable import TuistSupport

final class TSCUtilityVersionTests: XCTestCase {
    func test_version_when_allTagsPresent() {
        XCTAssertEqual(Version(unformattedString: "11.2.3"), Version(11, 2, 3))
    }

    func test_version_when_moreTagsPresent() {
        XCTAssertNil(Version(unformattedString: "11.2.3.3"))
    }

    func test_version_when_noTagsPresent() {
        XCTAssertNil(Version(unformattedString: "."))
    }

    func test_version_when_patchTagOmitted() {
        XCTAssertEqual(Version(unformattedString: "11.2"), Version(11, 2, 0))
    }

    func test_version_when_minorTagOmitted() {
        XCTAssertEqual(Version(unformattedString: "11"), Version(11, 0, 0))
    }

    func test_xcode_string_value() {
        // Given
        let subject = Version(12, 5, 1)

        // When
        let got = subject.xcodeStringValue

        // Then
        XCTAssertEqual(got, "1251")
    }
}
