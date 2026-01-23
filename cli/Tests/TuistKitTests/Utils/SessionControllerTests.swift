import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistKit
import TuistSupport

struct SessionControllerTests {
    private let fileSystem = FileSystem()
    private let subject = SessionController()

    @Test(.inTemporaryDirectory)
    func setup_createsSessionDirectory() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // When
        let (_, sessionPaths) = try await subject.setup(stateDirectory: temporaryDirectory)

        // Then
        #expect(try await fileSystem.exists(sessionPaths.sessionDirectory))
        #expect(try await fileSystem.exists(sessionPaths.logFilePath))
        #expect(sessionPaths.logFilePath.pathString.hasSuffix("logs.txt"))
        #expect(sessionPaths.networkFilePath.pathString.hasSuffix("network.har"))
    }

    @Test(.inTemporaryDirectory)
    func setup_cleansOldSessions() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // Given: Create an old session directory
        let oldSessionId = UUID().uuidString
        let oldSessionDirectory = temporaryDirectory.appending(components: ["sessions", oldSessionId])
        try await fileSystem.makeDirectory(at: oldSessionDirectory)
        try await fileSystem.touch(oldSessionDirectory.appending(component: "logs.txt"))

        let oldDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        try FileManager.default.setAttributes(
            [FileAttributeKey.creationDate: oldDate],
            ofItemAtPath: oldSessionDirectory.pathString
        )

        // When
        let (_, sessionPaths) = try await subject.setup(stateDirectory: temporaryDirectory)

        // Then
        let sessions = try await fileSystem.glob(directory: temporaryDirectory, include: ["sessions/*"]).collect()
        #expect(sessions.count == 1)
        #expect(sessions.first == sessionPaths.sessionDirectory)
    }

    @Test(.inTemporaryDirectory)
    func setup_migratesOldLogsDirectory() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // Given: Create old logs directory with old and recent logs
        let oldLogsDirectory = temporaryDirectory.appending(component: "logs")
        try await fileSystem.makeDirectory(at: oldLogsDirectory)

        let oldLogPath = oldLogsDirectory.appending(component: "\(UUID().uuidString).log")
        let recentLogPath = oldLogsDirectory.appending(component: "\(UUID().uuidString).log")
        try await fileSystem.touch(oldLogPath)
        try await fileSystem.touch(recentLogPath)

        let oldDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        try FileManager.default.setAttributes(
            [FileAttributeKey.creationDate: oldDate],
            ofItemAtPath: oldLogPath.pathString
        )

        // When
        _ = try await subject.setup(stateDirectory: temporaryDirectory)

        // Then: Old log should be deleted, recent log should remain
        let remainingLogs = try await fileSystem.glob(directory: oldLogsDirectory, include: ["*.log"]).collect()
        #expect(remainingLogs.count == 1)
        #expect(remainingLogs.first == recentLogPath)
    }

    @Test(.inTemporaryDirectory)
    func setup_removesEmptyOldLogsDirectory() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // Given: Create old logs directory with only old logs
        let oldLogsDirectory = temporaryDirectory.appending(component: "logs")
        try await fileSystem.makeDirectory(at: oldLogsDirectory)

        let oldLogPath = oldLogsDirectory.appending(component: "\(UUID().uuidString).log")
        try await fileSystem.touch(oldLogPath)

        let oldDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        try FileManager.default.setAttributes(
            [FileAttributeKey.creationDate: oldDate],
            ofItemAtPath: oldLogPath.pathString
        )

        // When
        _ = try await subject.setup(stateDirectory: temporaryDirectory)

        // Then: Old logs directory should be removed since it's empty
        #expect(try await !fileSystem.exists(oldLogsDirectory))
    }

    @Test(.inTemporaryDirectory)
    func setup_limitsMaxSessions() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // Given: Create more than 50 session directories
        let sessionsDirectory = temporaryDirectory.appending(component: "sessions")
        try await fileSystem.makeDirectory(at: sessionsDirectory)

        var sessionDates: [(path: AbsolutePath, date: Date)] = []
        for i in 0 ..< 55 {
            let sessionId = UUID().uuidString
            let sessionDirectory = sessionsDirectory.appending(component: sessionId)
            try await fileSystem.makeDirectory(at: sessionDirectory)
            try await fileSystem.touch(sessionDirectory.appending(component: "logs.txt"))

            let date = Calendar.current.date(byAdding: .hour, value: -i, to: Date())!
            try FileManager.default.setAttributes(
                [FileAttributeKey.creationDate: date],
                ofItemAtPath: sessionDirectory.pathString
            )
            sessionDates.append((path: sessionDirectory, date: date))
        }

        // When
        _ = try await subject.setup(stateDirectory: temporaryDirectory)

        // Then: Only 50 sessions should remain
        // Setup creates a new session first (making 56 total), then cleanup runs and keeps the newest 50
        let sessions = try await fileSystem.glob(directory: sessionsDirectory, include: ["*"]).collect()
        #expect(sessions.count == 50)
    }
}
