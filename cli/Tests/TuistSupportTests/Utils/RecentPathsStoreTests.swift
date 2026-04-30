import FileSystem
import Foundation
import Testing

@testable import TuistSupport

struct RecentPathsStoreTests {
    private let fileSystem = FileSystem()

    @Test func remember() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let date1 = Date()
            let path1 = temporaryDirectory.appending(component: "path-1")
            let date2 = Date()
            let path2 = temporaryDirectory.appending(component: "path-2")
            let subject = RecentPathsStore(storageDirectory: temporaryDirectory)

            // When
            try await subject.remember(path: path1, date: date1)
            try await subject.remember(path: path2, date: date2)

            // Then
            let got = try await subject.read()
            #expect(got == [path1: RecentPathMetadata(lastUpdated: date1), path2: RecentPathMetadata(lastUpdated: date2)])
        }
    }

    /// Reproduces the race in https://github.com/tuist/tuist/issues/9588 where
    /// concurrent invocations against the same storage directory either lose
    /// updates (read-modify-write without locking) or fail with
    /// `renamex_np ... File exists` when the temp file rename collides.
    /// Each "process" is simulated with its own `RecentPathsStore` instance to
    /// bypass the in-process `TaskLocal` and exercise the on-disk contract.
    @Test func remember_concurrent_writes_from_separate_stores() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let pathCount = 20
            let paths = (0 ..< pathCount).map { temporaryDirectory.appending(component: "path-\($0)") }
            let date = Date()

            // When
            try await withThrowingTaskGroup(of: Void.self) { group in
                for path in paths {
                    group.addTask {
                        let store = RecentPathsStore(storageDirectory: temporaryDirectory)
                        try await store.remember(path: path, date: date)
                    }
                }
                try await group.waitForAll()
            }

            // Then
            let got = try await RecentPathsStore(storageDirectory: temporaryDirectory).read()
            let expected = Dictionary(uniqueKeysWithValues: paths.map { ($0, RecentPathMetadata(lastUpdated: date)) })
            #expect(got == expected)
        }
    }
}
