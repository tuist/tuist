import Foundation
import Path
import Testing
@testable import XcodeGraph

struct CopyFilesActionTests {
    @Test func codable() throws {
        // Given
        let subject = CopyFilesAction(
            name: "name",
            destination: .frameworks,
            subpath: "subpath",
            files: [
                .file(path: try AbsolutePath(validating: "/path/to/file")),
            ]
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(CopyFilesAction.self, from: data)
        #expect(subject == decoded)
    }
}
