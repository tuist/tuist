import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class WorkspaceGenerationOptionsTests: TuistUnitTestCase {
    func test_codable_whenDefault() {
        // Given
        let subject = Workspace.GenerationOptions.automaticSchemeGeneration(.default)

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_whenDisabled() {
        // Given
        let subject = Workspace.GenerationOptions.automaticSchemeGeneration(.disabled)

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_whenEnabled() {
        // Given
        let subject = Workspace.GenerationOptions.automaticSchemeGeneration(.enabled)

        // Then
        XCTAssertCodable(subject)
    }
}
