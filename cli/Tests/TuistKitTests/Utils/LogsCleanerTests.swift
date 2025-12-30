import FileSystem
import Foundation
import Path
import Testing
import TuistKit

struct LogsControllerTests {
    private let fileSystem = FileSystem()
    private let subject = LogsController()

    @Test
    func setup() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let veryOldLogPath = temporaryDirectory.appending(components: ["logs", "\(UUID().uuidString).log"])
            let recentLogPath = temporaryDirectory.appending(components: ["logs", "\(UUID().uuidString).log"])
            try await fileSystem.makeDirectory(at: veryOldLogPath.parentDirectory)
            let oldDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

            try await fileSystem.touch(veryOldLogPath)
            try await fileSystem.touch(recentLogPath)

            try FileManager.default.setAttributes(
                [FileAttributeKey.creationDate: oldDate],
                ofItemAtPath: veryOldLogPath.pathString
            )

            // When
            let (_, newLogFilePath) = try await subject.setup(stateDirectory: temporaryDirectory)

            // Then
            let got = try await fileSystem.glob(directory: temporaryDirectory, include: ["logs/*"]).collect()
            #expect(got.contains(recentLogPath) == true)
            #expect(got.contains(try #require(newLogFilePath)) == true)
        }
    }
}
