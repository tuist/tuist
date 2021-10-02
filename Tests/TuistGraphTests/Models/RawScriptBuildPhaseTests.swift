import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class RawScriptBuildPhaseTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = RawScriptBuildPhase(
            name: "name",
            script: "script",
            showEnvVarsInLog: true,
            hashable: true
        )

        // Then
        XCTAssertCodable(subject)
    }
}
