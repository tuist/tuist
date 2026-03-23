import Foundation
import Path
import Testing
@testable import XcodeGraph

struct SourceFileTests {
    @Test func test_codable() throws {
        // Given
        let subject = SourceFile(
            path: try AbsolutePath(validating: "/path/to/file"),
            compilerFlags: "flag",
            contentHash: "hash"
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(SourceFile.self, from: data)
        #expect(subject == decoded)
    }
}
