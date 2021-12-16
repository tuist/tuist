import Foundation
import ProjectDescription
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistLoader

final class WorkspaceGenerationOptionsManifestMapperTests: XCTestCase {
    func test_from_whenAutomaticXcodeSchemeIsDefault() {
        // Given
        let manifest = ProjectDescription.Workspace.GenerationOptions.options(automaticXcodeSchemes: .default)

        // When
        let actual = TuistGraph.Workspace.GenerationOptions.from(manifest: manifest)

        // Then
        XCTAssertEqual(actual, .options(automaticXcodeSchemes: .default))
    }

    func test_from_whenAutomaticXcodeSchemeIsDisabled() {
        // Given
        let manifest = ProjectDescription.Workspace.GenerationOptions.options(automaticXcodeSchemes: .disabled)

        // When
        let actual = TuistGraph.Workspace.GenerationOptions.from(manifest: manifest)

        // Then
        XCTAssertEqual(actual, .options(automaticXcodeSchemes: .disabled))
    }

    func test_from_whenAutomaticXcodeSchemeIsEnabled() {
        // Given
        let manifest = ProjectDescription.Workspace.GenerationOptions.options(automaticXcodeSchemes: .enabled)

        // When
        let actual = TuistGraph.Workspace.GenerationOptions.from(manifest: manifest)

        // Then
        XCTAssertEqual(actual, .options(automaticXcodeSchemes: .enabled))
    }
}
