import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class WorkspaceGenerationOptionsTests: TuistUnitTestCase {
    func test_codable_whenDefault() {
        // Given
        let subject = Workspace.GenerationOptions.automaticXcodeSchemes(.default)

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_whenDisabled() {
        // Given
        let subject = Workspace.GenerationOptions.automaticXcodeSchemes(.disabled)

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_whenEnabled() {
        // Given
        let subject = Workspace.GenerationOptions.automaticXcodeSchemes(.enabled)

        // Then
        XCTAssertCodable(subject)
    }
}
