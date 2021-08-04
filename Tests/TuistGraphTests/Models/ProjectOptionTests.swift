import Foundation
import XCTest
@testable import TuistGraph

final class ProjectOptionTests: XCTestCase {
    func test_toJSON() {
        let subject = ProjectOption.textSettings(
            TextSettings(usesTabs: true, indentWidth: 0, tabWidth: 0, wrapsLines: true)
        )
        XCTAssertCodable(subject)
    }

    func test_extract_text_settings_from_options_array_when_exists() {
        // Given
        let settings = TextSettings.test()
        let options: [ProjectOption] = [.textSettings(settings)]

        // When
        let extractedSettings = options.textSettings

        // Then
        XCTAssertEqual(settings.usesTabs, extractedSettings?.usesTabs)
        XCTAssertEqual(settings.indentWidth, extractedSettings?.indentWidth)
        XCTAssertEqual(settings.tabWidth, extractedSettings?.tabWidth)
        XCTAssertEqual(settings.wrapsLines, extractedSettings?.wrapsLines)
    }

    func test_extract_text_settings_from_options_array_not_exists() {
        // Given
        let options: [ProjectOption] = []

        // When
        let extractedSettings = options.textSettings

        // Then
        XCTAssertNil(extractedSettings?.usesTabs)
        XCTAssertNil(extractedSettings?.indentWidth)
        XCTAssertNil(extractedSettings?.tabWidth)
        XCTAssertNil(extractedSettings?.wrapsLines)
    }
}
