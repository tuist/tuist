import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class ArchiveActionTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = ArchiveAction(
            configurationName: "name",
            revealArchiveInOrganizer: true,
            customArchiveName: "archiveName",
            preActions: [
                .init(
                    title: "preActionTitle",
                    scriptText: "text",
                    target: nil,
                    shellPath: nil,
                    showEnvVarsInLog: false
                ),
            ],
            postActions: [
                .init(
                    title: "postActionTitle",
                    scriptText: "text",
                    target: nil,
                    shellPath: nil,
                    showEnvVarsInLog: true
                ),
            ]
        )

        // Then
        XCTAssertCodable(subject)
    }
}
