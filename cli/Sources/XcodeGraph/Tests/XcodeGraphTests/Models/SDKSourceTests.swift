import Foundation
import Testing
@testable import XcodeGraph

struct SDKSourceTests {
    @Test func codable_developer() throws {
        // Given
        let subject = SDKSource.developer

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(SDKSource.self, from: data)
        #expect(subject == decoded)
    }

    @Test func codable_system() throws {
        // Given
        let subject = SDKSource.system

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(SDKSource.self, from: data)
        #expect(subject == decoded)
    }
}
