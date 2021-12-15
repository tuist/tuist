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
        let manifest = ProjectDescription.Workspace.GenerationOptions.automaticSchemeGeneration(.default)

        // When
        let actual = TuistGraph.Workspace.GenerationOptions.from(manifest: manifest)

        // Then
        XCTAssertEqual(actual, .automaticXcodeSchemes(.default))
    }

    func test_from_whenAutomaticSchemeGenerationIsDisabled() {
        // Given
        let manifest = ProjectDescription.Workspace.GenerationOptions.automaticSchemeGeneration(.disabled)

        // When
        let actual = TuistGraph.Workspace.GenerationOptions.from(manifest: manifest)

        // Then
        XCTAssertEqual(actual, .automaticXcodeSchemes(.disabled))
    }

    func test_from_whenAutomaticSchemeGenerationIsEnabled() {
        // Given
        let manifest = ProjectDescription.Workspace.GenerationOptions.automaticSchemeGeneration(.enabled)

        // When
        let actual = TuistGraph.Workspace.GenerationOptions.from(manifest: manifest)

        // Then
        XCTAssertEqual(actual, .automaticXcodeSchemes(.enabled))
    }
}
