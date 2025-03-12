import FileSystem
import Foundation
import Testing

@testable import TuistSupport

struct RecentPathsRecorderTests {
    private let fileSystem = FileSystem()

    @Test func recordPaths() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let date1 = Date()
            let path1 = temporaryDirectory.appending(component: "path-1")
            let date2 = Date()
            let path2 = temporaryDirectory.appending(component: "path-2")
            let subject = RecentPathsRecorder(storageDirectory: temporaryDirectory)

            // When
            try await subject.record(path: path1, date: date1)
            try await subject.record(path: path2, date: date2)

            // Then
            let got = try await subject.read()
            #expect(got == [path1: date1, path2: date2])
        }
    }
}
