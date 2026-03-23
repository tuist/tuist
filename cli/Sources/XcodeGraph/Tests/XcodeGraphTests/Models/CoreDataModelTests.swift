import Foundation
import Path
import Testing
@testable import XcodeGraph

struct CoreDataModelTests {
    @Test func test_codable() throws {
        // Given
        let subject = CoreDataModel(
            path: try AbsolutePath(validating: "/path/to/model"),
            versions: [
                try AbsolutePath(validating: "/path/to/version"),
            ],
            currentVersion: "1.1.1"
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(CoreDataModel.self, from: data)
        #expect(subject == decoded)
    }
}
