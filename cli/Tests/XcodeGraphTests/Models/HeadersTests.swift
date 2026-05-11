import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class HeadersTests: XCTestCase {
    func test_codable() throws {
        // Given
        let subject = Headers(
            public: [
                try AbsolutePath(validating: "/path/to/public/header"),
            ],
            private: [
                try AbsolutePath(validating: "/path/to/private/header"),
            ],
            project: [
                try AbsolutePath(validating: "/path/to/project/header"),
            ]
        )

        // Then
        XCTAssertCodable(subject)
    }
}
