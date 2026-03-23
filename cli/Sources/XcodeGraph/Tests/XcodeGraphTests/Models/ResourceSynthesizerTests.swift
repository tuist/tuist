import Foundation
import Testing
@testable import XcodeGraph

struct ResourceSynthesizerTests {
    @Test func test_codable() throws {
        // Given
        let subject = ResourceSynthesizer(
            parser: .coreData,
            parserOptions: ["key": "value"],
            extensions: [
                "extension1",
                "extension2",
            ],
            template: .defaultTemplate("template")
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(ResourceSynthesizer.self, from: data)
        #expect(subject == decoded)
    }
}
