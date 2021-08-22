import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class ProfileActionTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = ProfileAction(
            configurationName: "name",
            executable: .init(
                projectPath: "/path/to/project",
                name: "name"
            ),
            arguments: .init(
                environmentVariables: [
                    .init(
                        key: "key",
                        value: "value",
                        isEnabled: true
                    ),
                ],
                launchArguments: [
                    .init(
                        name: "name",
                        isEnabled: false
                    ),
                ]
            )
        )

        // Then
        XCTAssertCodable(subject)
    }
}
