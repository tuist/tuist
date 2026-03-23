import Foundation
import Testing
@testable import XcodeGraph

struct SchemeTests {
    @Test func test_codable() throws {
        // Given
        let subject = Scheme.test(name: "name", shared: true)

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(Scheme.self, from: data)
        #expect(subject == decoded)
    }
}
