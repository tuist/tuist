import XCTest
@testable import TuistCache
@testable import TuistSupportTesting

final class XCFrameworkBuilderErrorTests: TuistUnitTestCase {
    func test_type_when_nonFrameworkTarget() {
        // Given
        let subject = XCFrameworkBuilderError.nonFrameworkTarget("App")

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }

    func test_description_when_nonFrameworkTarget() {
        // Given
        let subject = XCFrameworkBuilderError.nonFrameworkTarget("App")

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "Can't generate an .xcframework from the target 'App' because it's not a framework target")
    }
}
