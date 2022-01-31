import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class WorkspaceAutomaticSchemeGenerationTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = Workspace.GenerationOptions.AutomaticXcodeSchemes.default

        // Then
        XCTAssertCodable(subject)
    }

    func test_value_whenDefault() {
        // Given
        let subject = Workspace.GenerationOptions.AutomaticXcodeSchemes.default

        // When
        let actual = subject.value

        // Then
        XCTAssertNil(actual)
    }

    func test_value_whenDisabled() {
        // Given
        let subject = Workspace.GenerationOptions.AutomaticXcodeSchemes.disabled

        // When
        let actual = subject.value

        // Then
        XCTAssertEqual(actual, false)
    }

    func test_value_whenEnabled() {
        // Given
        let subject = Workspace.GenerationOptions.AutomaticXcodeSchemes.enabled

        // When
        let actual = subject.value

        // Then
        XCTAssertEqual(actual, true)
    }
}
