import Foundation
import Testing
@testable import XcodeGraph

struct WorkspaceGenerationOptionsTests {
    @Test func test_codable_whenDefault() throws {
        // Given
        let subject = Workspace.GenerationOptions.test()

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(Workspace.self, from: data)
        #expect(subject == decoded)
    }
}
