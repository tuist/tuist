import Foundation
import XCTest
@testable import TuistSupport

final class DecodingFirstTests: XCTestCase {
    func test_decodes_only_first() throws {
        // Given
        let holderJson = #"{"element": ["elementOne", "elementTwo"]}"#

        // When
        let holder = try JSONDecoder().decode(
            ArrayHolder.self,
            from: try XCTUnwrap(holderJson.data(using: .utf8))
        )

        // Then
        XCTAssertEqual(holder.element, "elementOne")
    }

    func test_decode_fails_when_no_values() throws {
        // Given
        let holderJson = #"{"element": []}"#

        // Then
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ArrayHolder.self,
                from: try XCTUnwrap(holderJson.data(using: .utf8))
            )
        )
    }
}

private struct ArrayHolder: Codable {
    @DecodingFirst
    var element: String
}
