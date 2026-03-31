import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCASAnalytics
@testable import TuistKit

struct AnalyticsStateControllerTests {
    private let fileSystem = FileSystem()
    private let database = MockCASAnalyticsDatabasing()

    @Test(.inTemporaryDirectory)
    func clean_removesLegacyFileDirectories() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        for dir in ["cas", "nodes", "keyvalue"] {
            let dirPath = temporaryDirectory.appending(component: dir)
            try await fileSystem.makeDirectory(at: dirPath)
            try await fileSystem.touch(dirPath.appending(component: "file.json"))
        }

        given(database).removeOldEntries(olderThan: .any).willReturn()

        try await AnalyticsStateController.clean(
            fileSystem: fileSystem,
            database: database,
            stateDirectory: temporaryDirectory
        )

        #expect(try await !fileSystem.exists(temporaryDirectory.appending(component: "cas")))
        #expect(try await !fileSystem.exists(temporaryDirectory.appending(component: "nodes")))
        #expect(try await !fileSystem.exists(temporaryDirectory.appending(component: "keyvalue")))
    }

    @Test(.inTemporaryDirectory)
    func clean_removesLegacyLogsDirectory() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let logsDirectory = temporaryDirectory.appending(component: "logs")
        try await fileSystem.makeDirectory(at: logsDirectory)
        try await fileSystem.touch(logsDirectory.appending(component: "old-log.txt"))

        given(database).removeOldEntries(olderThan: .any).willReturn()

        try await AnalyticsStateController.clean(
            fileSystem: fileSystem,
            database: database,
            stateDirectory: temporaryDirectory
        )

        #expect(try await !fileSystem.exists(logsDirectory))
    }

    @Test(.inTemporaryDirectory)
    func clean_removesOldDatabaseEntries() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        given(database).removeOldEntries(olderThan: .any).willReturn()

        try await AnalyticsStateController.clean(
            fileSystem: fileSystem,
            database: database,
            stateDirectory: temporaryDirectory
        )

        verify(database).removeOldEntries(olderThan: .any).called(1)
    }

    @Test(.inTemporaryDirectory)
    func clean_handlesNonExistentDirectories() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        given(database).removeOldEntries(olderThan: .any).willReturn()

        try await AnalyticsStateController.clean(
            fileSystem: fileSystem,
            database: database,
            stateDirectory: temporaryDirectory
        )
    }
}
