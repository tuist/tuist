import Foundation
import Testing
@testable import XcodeGraph

struct GraphTargetTests {
    @Test func test_codable() throws {
        // Given
        let subject = GraphTarget.test()

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(GraphTarget.self, from: data)
        #expect(subject == decoded)
    }
}
