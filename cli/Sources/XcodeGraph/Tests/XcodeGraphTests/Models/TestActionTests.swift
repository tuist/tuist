import Foundation
import Testing
@testable import XcodeGraph

struct TestActionTests {
    @Test func codable() throws {
        // Given
        let subject = TestAction.test()

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(TestAction.self, from: data)
        #expect(subject == decoded)
    }
}
