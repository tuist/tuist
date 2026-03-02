import Foundation
import XCTest
@testable import XcodeGraph

final class SettingsDictionaryExtrasTest: XCTestCase {
    func testOverlay_addsPlatformSpecifierWhenSettingsDiffer() {
        // Given
        var settings: [String: SettingValue] = [
            "A": "a value",
            "B": "b value",
        ]

        // When
        settings.overlay(with: [
            "A": "overlayed value",
            "B": "b value",
            "C": "c value",
        ], for: .macOS)

        // Then
        XCTAssertEqual(settings, [
            "A[sdk=macosx*]": "overlayed value",
            "A": "a value",
            "B": "b value",
            "C[sdk=macosx*]": "c value",
        ])
    }
}
