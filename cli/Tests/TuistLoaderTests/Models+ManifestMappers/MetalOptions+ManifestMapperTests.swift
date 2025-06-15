import Foundation
import ProjectDescription
import TuistTesting
import XcodeGraph
import XCTest

@testable import TuistLoader

final class MetalOptionsManifestMapperTests: TuistUnitTestCase {
    func test_from() throws {
        // Given
        let manifest: ProjectDescription.MetalOptions = .options(
            apiValidation: true,
            shaderValidation: false,
            showGraphicsOverview: false,
            logGraphicsOverview: false
        )

        // When
        let got = XcodeGraph.MetalOptions.from(manifest: manifest)

        // Then
        XCTAssertBetterEqual(
            got,
            XcodeGraph.MetalOptions(
                apiValidation: true,
                shaderValidation: false,
                showGraphicsOverview: false,
                logGraphicsOverview: false
            )
        )
    }
}
