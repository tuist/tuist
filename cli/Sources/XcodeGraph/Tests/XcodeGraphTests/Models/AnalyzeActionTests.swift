import Foundation
import Testing
@testable import XcodeGraph

struct AnalyzeActionTests {
    @Test func codable() throws {
        // Given
        let subject = AnalyzeAction(configurationName: "name")

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(AnalyzeAction.self, from: data)
        #expect(subject == decoded)
    }
}
