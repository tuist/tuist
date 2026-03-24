import Foundation
import Path
import Testing
@testable import XcodeGraph

struct WorkspaceTests {
    @Test func codable() throws {
        // Given
        let subject = Workspace.test(
            path: try AbsolutePath(validating: "/path/to/workspace"),
            name: "name"
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(Workspace.self, from: data)
        #expect(subject == decoded)
    }
}
