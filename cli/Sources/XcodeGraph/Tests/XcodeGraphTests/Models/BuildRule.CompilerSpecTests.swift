import Foundation
import Testing
@testable import XcodeGraph

struct BuildRuleCompilerSpecTests {
    @Test func test_codable() throws {
        // Given
        let subject = BuildRule.CompilerSpec.customScript

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(BuildRule.self, from: data)
        #expect(subject == decoded)
    }
}
