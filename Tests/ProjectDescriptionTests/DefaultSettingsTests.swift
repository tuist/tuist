import XCTest
@testable import ProjectDescription

final class DefaultSettingsTests: XCTestCase {
    func test_recommended_toJSON() {
        let subject = DefaultSettings.recommended(excluding: ["exclude"])
        XCTAssertCodable(subject)
    }

    func test_essential_toJSON() {
        let subject = DefaultSettings.essential(excluding: ["exclude"])
        XCTAssertCodable(subject)
    }

    func test_none_toJSON() {
        let subject = DefaultSettings.none
        XCTAssertCodable(subject)
    }
}
