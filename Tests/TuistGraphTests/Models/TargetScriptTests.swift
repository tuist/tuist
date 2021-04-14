import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class TargetScriptTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = TargetScript(
            name: "name",
            script: "script",
            showEnvVarsInLog: true,
            hashable: true
        )
        
        // Then
        XCTAssertCodable(subject)
    }
}
