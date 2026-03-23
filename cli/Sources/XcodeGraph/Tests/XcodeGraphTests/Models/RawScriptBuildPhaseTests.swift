import Foundation
import Testing
@testable import XcodeGraph

struct RawScriptBuildPhaseTests {
    @Test func test_codable() throws {
        // Given
        let subject = RawScriptBuildPhase(
            name: "name",
            script: "script",
            showEnvVarsInLog: true,
            hashable: true
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(RawScriptBuildPhase.self, from: data)
        #expect(subject == decoded)
    }
}
