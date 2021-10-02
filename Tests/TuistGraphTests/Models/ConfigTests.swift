import Foundation
import XCTest

@testable import TuistGraph

final class ConfigTests: XCTestCase {
    func test_codeCoverageMode_returnsTheRightValue_whenRelevant() {
        let modes = [
            CodeCoverageMode.all,
            .relevant,
            .targets([TargetReference(projectPath: "/", name: "Target")]),
        ]

        modes.forEach { mode in
            // Given
            let subject = Config(
                compatibleXcodeVersions: .all,
                cloud: nil,
                cache: nil,
                swiftVersion: nil,
                plugins: [],
                generationOptions: [
                    .enableCodeCoverage(mode),
                ],
                path: nil
            )

            // Then
            XCTAssertEqual(mode, subject.codeCoverageMode)
        }
    }

    func test_codeCoverageMode_returnsNil_whenNotGiven() {
        // Given
        let subject = Config(
            compatibleXcodeVersions: .all,
            cloud: nil,
            cache: nil,
            swiftVersion: nil,
            plugins: [],
            generationOptions: [],
            path: nil
        )

        // Then
        XCTAssertNil(subject.codeCoverageMode)
    }
}
