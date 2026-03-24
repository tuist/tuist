import Foundation
import Testing
@testable import XcodeGraph

struct SettingsDictionaryExtrasTest {
    @Test func overlay_addsPlatformSpecifierWhenSettingsDiffer() {
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
        #expect(settings == [
            "A[sdk=macosx*]": "overlayed value",
            "A": "a value",
            "B": "b value",
            "C[sdk=macosx*]": "c value",
        ])
    }
}
