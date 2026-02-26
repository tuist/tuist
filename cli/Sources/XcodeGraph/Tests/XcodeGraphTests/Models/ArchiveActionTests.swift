import Foundation
import XCTest
@testable import XcodeGraph

final class ArchiveActionTests: XCTestCase {
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
