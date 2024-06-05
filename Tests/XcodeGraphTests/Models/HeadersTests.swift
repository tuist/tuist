import Foundation
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class HeadersTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = Headers(
            public: [
                "/path/to/public/header",
            ],
            private: [
                "/path/to/private/header",
            ],
            project: [
                "/path/to/project/header",
            ]
        )

        // Then
        XCTAssertCodable(subject)
    }
}
