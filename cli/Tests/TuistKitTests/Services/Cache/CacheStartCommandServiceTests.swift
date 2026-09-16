import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistEnvironment
import TuistTesting

@testable import TuistKit

struct CacheStartCommandServiceTests {
    private let fileSystem = FileSystem()
    private let subject = CacheStartCommandService()

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func removes_the_launch_agent_and_socket_of_the_retired_daemon() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        let plistPath = environment.homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.cache.organization_project.plist"
        )
        let socketPath = environment.cacheSocketPath(for: "organization/project")
        try await fileSystem.makeDirectory(at: plistPath.parentDirectory)
        try await fileSystem.writeText("", at: plistPath)
        try await fileSystem.writeText("", at: socketPath)

        // When
        try await subject.run(fullHandle: "organization/project")

        // Then
        #expect(try await fileSystem.exists(plistPath) == false)
        #expect(try await fileSystem.exists(socketPath) == false)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func succeeds_when_nothing_is_left_to_remove() async throws {
        try await subject.run(fullHandle: "organization/project")
    }
}
