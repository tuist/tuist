import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class ArgumentsTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = Arguments(
            environmentVariables: [
                "key": EnvironmentVariable(value: "value", isEnabled: true),
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
