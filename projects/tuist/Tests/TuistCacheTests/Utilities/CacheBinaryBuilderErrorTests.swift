import XCTest
@testable import TuistCache
@testable import TuistSupportTesting

final class CacheBinaryBuilderErrorTests: TuistUnitTestCase {
    func test_type_when_nonFrameworkTargetForXCFramework() {
        // Given
        let subject = CacheBinaryBuilderError.nonFrameworkTargetForXCFramework("App")

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }

    func test_description_when_nonFrameworkTargetForXCFramework() {
        // Given
        let subject = CacheBinaryBuilderError.nonFrameworkTargetForXCFramework("App")

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "Can't generate an .xcframework from the target 'App' because it's not a framework target")
    }

    func test_type_when_nonFrameworkTargetForFramework() {
        // Given
        let subject = CacheBinaryBuilderError.nonFrameworkTargetForFramework("App")

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }

    func test_description_when_nonFrameworkTargetForFramework() {
        // Given
        let subject = CacheBinaryBuilderError.nonFrameworkTargetForFramework("App")

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "Can't generate a .framework from the target 'App' because it's not a framework target")
    }
}
