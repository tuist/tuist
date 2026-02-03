import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
@testable import TuistKit

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
    func clean_removesOldSessions() async throws {
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

        let (_, sessionPaths) = try await subject.setup(stateDirectory: temporaryDirectory)

        // When
        try await SessionController.clean(fileSystem: fileSystem, stateDirectory: temporaryDirectory)

        // Then
        let sessions = try await fileSystem.glob(directory: temporaryDirectory, include: ["sessions/*"]).collect()
        #expect(sessions.count == 1)
        #expect(sessions.first == sessionPaths.sessionDirectory)
    }

    @Test(.inTemporaryDirectory)
    func clean_limitsMaxSessions() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // Given: Create more than 50 session directories
        let sessionsDirectory = temporaryDirectory.appending(component: "sessions")
        try await fileSystem.makeDirectory(at: sessionsDirectory)

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
        }

        // When
        try await SessionController.clean(fileSystem: fileSystem, stateDirectory: temporaryDirectory)

        // Then: Only 50 sessions should remain
        let sessions = try await fileSystem.glob(directory: sessionsDirectory, include: ["*"]).collect()
        #expect(sessions.count == 50)
    }
}
