import Foundation
import Testing
@testable import TuistSupport

struct DecodingFirstTests {
    @Test
    func decodes_only_first() throws {
        // Given
        let holderJson = #"{"element": ["elementOne", "elementTwo"]}"#

        // When
        let holder = try JSONDecoder().decode(
            ArrayHolder.self,
            from: try #require(holderJson.data(using: .utf8))
        )

        // Then
        #expect(holder.element == "elementOne")
    }

    @Test
    func decode_fails_when_no_values() throws {
        // Given
        let holderJson = #"{"element": []}"#

        // Then
        #expect(throws: (any Error).self) { try JSONDecoder().decode(
            ArrayHolder.self,
            from: try #require(holderJson.data(using: .utf8))
        ) }
    }
}

private struct ArrayHolder: Codable {
    @DecodingFirst
    var element: String
}
