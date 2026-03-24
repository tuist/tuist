import Foundation
import Testing
@testable import XcodeGraph

struct RequirementTests {
    @Test func codable_range() throws {
        // Given
        let subject = Requirement.range(from: "1.0.0", to: "2.0.0")

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(Requirement.self, from: data)
        #expect(subject == decoded)
    }

    @Test func codable_upToNextMajor() throws {
        // Given
        let subject = Requirement.upToNextMajor("1.2.3")

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(Requirement.self, from: data)
        #expect(subject == decoded)
    }
}
