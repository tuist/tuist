import Foundation
import Testing
@testable import XcodeGraph

struct DependenciesGraphTests {
    @Test func codable_xcframework() throws {
        // Given
        let subject = DependenciesGraph.test()

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(DependenciesGraph.self, from: data)
        #expect(subject == decoded)
    }
}
