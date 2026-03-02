import Foundation
import XCTest
@testable import XcodeGraph

final class ArgumentsTests: XCTestCase {
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
