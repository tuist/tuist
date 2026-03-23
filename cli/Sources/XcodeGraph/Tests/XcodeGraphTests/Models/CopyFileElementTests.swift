import Foundation
import Path
import Testing
@testable import XcodeGraph

struct CopyFileElementTests {
    @Test func test_codable_file() throws {
        // Given
        let subject = CopyFileElement.file(path: try AbsolutePath(validating: "/path/to/file"), condition: .when([.macos]))

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(CopyFileElement.self, from: data)
        #expect(subject == decoded)
    }

    @Test func test_codable_folderReference() throws {
        // Given
        let subject = CopyFileElement.folderReference(
            path: try AbsolutePath(validating: "/folder/reference"),
            condition: .when([.macos])
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(CopyFileElement.self, from: data)
        #expect(subject == decoded)
    }
}
