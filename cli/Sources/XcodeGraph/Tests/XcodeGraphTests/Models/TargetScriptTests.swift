import Foundation
import Path
import Testing
@testable import XcodeGraph

private let script = """
echo 'Hello World'
wd=$(pwd)
echo "$wd"
"""

struct TargetScriptTests {
    @Test func test_codable() throws {
        // Given
        let subject = TargetScript(name: "name", order: .pre, script: .embedded(script))

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(TargetScript.self, from: data)
        #expect(subject == decoded)
    }
}
