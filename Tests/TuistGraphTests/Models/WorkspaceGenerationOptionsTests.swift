import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class WorkspaceGenerationOptionsTests: TuistUnitTestCase {
    func test_codable_whenDefault() {
        // Given
        let subject = Workspace.GenerationOptions.automaticSchemaGeneration(.default)

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_whenDisabled() {
        // Given
        let subject = Workspace.GenerationOptions.automaticSchemaGeneration(.disabled)

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_whenEnabled() {
        // Given
        let subject = Workspace.GenerationOptions.automaticSchemaGeneration(.enabled)

        // Then
        XCTAssertCodable(subject)
    }
}
