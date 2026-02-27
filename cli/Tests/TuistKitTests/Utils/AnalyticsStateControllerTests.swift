import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
@testable import TuistKit

struct AnalyticsStateControllerTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory)
    func clean_removesOldAnalyticsFiles() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let casDirectory = temporaryDirectory.appending(component: "cas")
        let nodesDirectory = temporaryDirectory.appending(component: "nodes")
        let keyValueReadDirectory = temporaryDirectory.appending(components: ["keyvalue", "read"])
        let keyValueWriteDirectory = temporaryDirectory.appending(components: ["keyvalue", "write"])

        try await fileSystem.makeDirectory(at: casDirectory)
        try await fileSystem.makeDirectory(at: nodesDirectory)
        try await fileSystem.makeDirectory(at: keyValueReadDirectory)
        try await fileSystem.makeDirectory(at: keyValueWriteDirectory)

        let oldCasFile = casDirectory.appending(component: "old-cas.json")
        let oldNodesFile = nodesDirectory.appending(component: "old-node")
        let oldKVReadFile = keyValueReadDirectory.appending(component: "old-read.json")
        let oldKVWriteFile = keyValueWriteDirectory.appending(component: "old-write.json")

        for file in [oldCasFile, oldNodesFile, oldKVReadFile, oldKVWriteFile] {
            try await fileSystem.touch(file)
        }

        let oldDate = Calendar.current.date(byAdding: .hour, value: -2, to: Date())!
        for file in [oldCasFile, oldNodesFile, oldKVReadFile, oldKVWriteFile] {
            try FileManager.default.setAttributes(
                [FileAttributeKey.creationDate: oldDate],
                ofItemAtPath: file.pathString
            )
        }

        // When
        try await AnalyticsStateController.clean(
            fileSystem: fileSystem,
            stateDirectory: temporaryDirectory
        )

        // Then
        #expect(try await !fileSystem.exists(oldCasFile))
        #expect(try await !fileSystem.exists(oldNodesFile))
        #expect(try await !fileSystem.exists(oldKVReadFile))
        #expect(try await !fileSystem.exists(oldKVWriteFile))
    }

    @Test(.inTemporaryDirectory)
    func clean_keepsRecentAnalyticsFiles() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let casDirectory = temporaryDirectory.appending(component: "cas")
        let nodesDirectory = temporaryDirectory.appending(component: "nodes")
        let keyValueReadDirectory = temporaryDirectory.appending(components: ["keyvalue", "read"])

        try await fileSystem.makeDirectory(at: casDirectory)
        try await fileSystem.makeDirectory(at: nodesDirectory)
        try await fileSystem.makeDirectory(at: keyValueReadDirectory)

        let recentCasFile = casDirectory.appending(component: "recent-cas.json")
        let recentNodesFile = nodesDirectory.appending(component: "recent-node")
        let recentKVReadFile = keyValueReadDirectory.appending(component: "recent-read.json")

        for file in [recentCasFile, recentNodesFile, recentKVReadFile] {
            try await fileSystem.touch(file)
        }

        // When
        try await AnalyticsStateController.clean(
            fileSystem: fileSystem,
            stateDirectory: temporaryDirectory
        )

        // Then
        #expect(try await fileSystem.exists(recentCasFile))
        #expect(try await fileSystem.exists(recentNodesFile))
        #expect(try await fileSystem.exists(recentKVReadFile))
    }

    @Test(.inTemporaryDirectory)
    func clean_removesLegacyLogsDirectory() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let logsDirectory = temporaryDirectory.appending(component: "logs")
        try await fileSystem.makeDirectory(at: logsDirectory)
        try await fileSystem.touch(logsDirectory.appending(component: "old-log.txt"))

        // When
        try await AnalyticsStateController.clean(
            fileSystem: fileSystem,
            stateDirectory: temporaryDirectory
        )

        // Then
        #expect(try await !fileSystem.exists(logsDirectory))
    }

    @Test(.inTemporaryDirectory)
    func clean_handlesNonExistentDirectories() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // When/Then -- should not throw
        try await AnalyticsStateController.clean(
            fileSystem: fileSystem,
            stateDirectory: temporaryDirectory
        )
    }
}
