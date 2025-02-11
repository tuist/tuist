import FileSystem
import Foundation
import Testing
import TuistKit

struct LogCleanerTests {
    private let fileSystem = FileSystem()
    private let subject = LogsCleaner()

    @Test("deletes logs that are older than 5 days")
    func deleteOldLogs() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let veryOldLogPath = temporaryDirectory.appending(component: "\(UUID().uuidString).log")
            let recentLogPath = temporaryDirectory.appending(component: "\(UUID().uuidString).log")
            let oldDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

            try await fileSystem.touch(veryOldLogPath)
            try await fileSystem.touch(recentLogPath)
            try FileManager.default.setAttributes(
                [FileAttributeKey.creationDate: oldDate],
                ofItemAtPath: veryOldLogPath.pathString
            )

            // When
            try await subject.clean(logsDirectory: temporaryDirectory)

            // Then
            let got = try await fileSystem.glob(directory: temporaryDirectory, include: ["*"]).collect()
            #expect(got.count == 1)
            #expect(got.first == recentLogPath)
        }
    }
}
