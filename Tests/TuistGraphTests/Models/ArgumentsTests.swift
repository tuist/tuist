import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class ArgumentsTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = Arguments(
            environment: [
                "key": "value",
            ],
            launchArguments: [
                .init(
                    name: "name",
                    isEnabled: true
                ),
            ]
        )

        // Then
        XCTAssertCodable(subject)
    }
}
