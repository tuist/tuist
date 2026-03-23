import Foundation
import Testing
@testable import XcodeGraph

struct ProjectGroupTests {
    @Test func test_codable() throws {
        // Given
        let subject = ProjectGroup.group(name: "name")

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(ProjectGroup.self, from: data)
        #expect(subject == decoded)
    }
}
