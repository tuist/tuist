import Foundation
import ProjectDescription
import Testing
import TuistTesting
import XcodeGraph

@testable import TuistLoader

struct MetalOptionsManifestMapperTests {
    @Test func test_from() throws {
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
        #expect(
            got ==
                XcodeGraph.MetalOptions(
                    apiValidation: true,
                    shaderValidation: false,
                    showGraphicsOverview: false,
                    logGraphicsOverview: false
                )
        )
    }
}
