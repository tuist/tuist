import StaticFramework
import XCTest
@testable import AppClip1

final class AppClipTests: XCTestCase {
    func testExample() {
        XCTAssertTrue(2 == 2)
    }

    func testStaticFrameworkCode() {
        // Given
        let subject = AppClipModel()

        // When
        let result = subject.makeStaticFrameworkType()

        // Then
        XCTAssertEqual(result.name, "AppClip")
    }

    func testStaticFrameworkTypeIdentifier() {
        // Given
        let subject = AppClipModel()

        // When
        let result = subject.staticFrameworkTypeIdentifier()

        // Then
        // In the event of duplicate symbols, the type identifiers
        // will mismatch when referenced from two different sources
        XCTAssertEqual(result, StaticFrameworkType.typeIdentifier)
    }
}
