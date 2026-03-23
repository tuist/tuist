import Foundation
import Path
import Testing
@testable import XcodeGraph

struct FileElementTests {
    @Test func test_codable_file() throws {
        // Given
        let subject = FileElement.file(path: try AbsolutePath(validating: "/path/to/file"))

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(FileElement.self, from: data)
        #expect(subject == decoded)
    }

    @Test func test_codable_folderReference() throws {
        // Given
        let subject = FileElement.folderReference(path: try AbsolutePath(validating: "/folder/reference"))

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(FileElement.self, from: data)
        #expect(subject == decoded)
    }
}
