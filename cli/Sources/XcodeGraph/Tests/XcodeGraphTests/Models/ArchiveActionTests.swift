import Foundation
import Testing
@testable import XcodeGraph

struct ArchiveActionTests {
    @Test func test_codable() throws {
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
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(ArchiveAction.self, from: data)
        #expect(subject == decoded)
    }
}
