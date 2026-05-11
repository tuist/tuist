import Foundation
import XCTest
@testable import XcodeGraph

final class RawScriptBuildPhaseTests: XCTestCase {
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
