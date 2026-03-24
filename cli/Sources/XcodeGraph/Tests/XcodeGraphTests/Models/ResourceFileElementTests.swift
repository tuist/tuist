import Foundation
import Path
import Testing
@testable import XcodeGraph

struct ResourceFileElementTests {
    @Test func codable_file() throws {
        // Given
        let subject = ResourceFileElement.file(
            path: try AbsolutePath(validating: "/path/to/element"),
            tags: [
                "tag",
            ]
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(ResourceFileElement.self, from: data)
        #expect(subject == decoded)
    }

    @Test func codable_folderReference() throws {
        // Given
        let subject = ResourceFileElement.folderReference(
            path: try AbsolutePath(validating: "/path/to/folder"),
            tags: [
                "tag",
            ]
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(ResourceFileElement.self, from: data)
        #expect(subject == decoded)
    }
}
