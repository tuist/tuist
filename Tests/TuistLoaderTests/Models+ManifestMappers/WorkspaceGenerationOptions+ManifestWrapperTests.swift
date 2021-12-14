import Foundation
import ProjectDescription
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistLoader

final class WorkspaceGenerationOptionsManifestMapperTests: XCTestCase {
    func test_from_whenAutomaticSchemeGenerationIsDefault() {
        // Given
        let manifest = ProjectDescription.Workspace.GenerationOptions.automaticSchemaGeneration(.default)

        // When
        let actual = TuistGraph.Workspace.GenerationOptions.from(manifest: manifest)

        // Then
        XCTAssertEqual(actual, .automaticSchemaGeneration(.default))
    }

    func test_from_whenAutomaticSchemeGenerationIsDisabled() {
        // Given
        let manifest = ProjectDescription.Workspace.GenerationOptions.automaticSchemaGeneration(.disabled)

        // When
        let actual = TuistGraph.Workspace.GenerationOptions.from(manifest: manifest)

        // Then
        XCTAssertEqual(actual, .automaticSchemaGeneration(.disabled))
    }

    func test_from_whenAutomaticSchemeGenerationIsEnabled() {
        // Given
        let manifest = ProjectDescription.Workspace.GenerationOptions.automaticSchemaGeneration(.enabled)

        // When
        let actual = TuistGraph.Workspace.GenerationOptions.from(manifest: manifest)

        // Then
        XCTAssertEqual(actual, .automaticSchemaGeneration(.enabled))
    }
}
