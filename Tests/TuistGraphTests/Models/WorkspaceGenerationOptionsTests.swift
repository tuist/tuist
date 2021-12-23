import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class WorkspaceGenerationOptionsTests: TuistUnitTestCase {
    func test_codable_whenDefault() {
        // Given
        let subject = Workspace.GenerationOptions.options(automaticXcodeSchemes: .default)

        // Then
        XCTAssertCodable(subject)
    }

    func test_value_whenDefault() {
        // Given
        let subject = Workspace.GenerationOptions.AutomaticSchemeMode.default

        // Then
        XCTAssertNil(subject.value)
    }

    func test_value_whenDisabled() {
        // Given
        let subject = Workspace.GenerationOptions.AutomaticSchemeMode.disabled

        // Then
        XCTAssertEqual(subject.value, false)
    }

    func test_value_whenEnabled() {
        // Given
        let subject = Workspace.GenerationOptions.AutomaticSchemeMode.enabled

        // Then
        XCTAssertEqual(subject.value, true)
    }
}
