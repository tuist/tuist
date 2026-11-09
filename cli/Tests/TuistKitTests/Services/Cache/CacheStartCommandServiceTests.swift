import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistEnvironment
import TuistLaunchctl
import TuistTesting

@testable import TuistKit

struct CacheStartCommandServiceTests {
    private let fileSystem = FileSystem()
    private let launchctlController = MockLaunchctlControlling()
    private let subject: CacheStartCommandService

    init() {
        subject = CacheStartCommandService(fileSystem: fileSystem, launchctlController: launchctlController)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func removes_the_launch_agent_and_socket_of_the_retired_daemon_before_booting_it_out() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        let plistPath = environment.homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.cache.organization_project.plist"
        )
        let socketPath = environment.cacheSocketPath(for: "organization/project")
        try await fileSystem.makeDirectory(at: plistPath.parentDirectory)
        try await fileSystem.writeText("", at: plistPath)
        try await fileSystem.writeText("", at: socketPath)
        given(launchctlController)
            .bootout(label: .any)
            .willProduce { _ in
                #expect(FileManager.default.fileExists(atPath: plistPath.pathString) == false)
                #expect(FileManager.default.fileExists(atPath: socketPath.pathString) == false)
            }

        // When
        try await subject.run(fullHandle: "organization/project")

        // Then
        verify(launchctlController)
            .bootout(label: .value("tuist.cache.organization_project"))
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func succeeds_when_nothing_is_left_to_remove_and_the_agent_cannot_be_booted_out() async throws {
        // Given
        given(launchctlController)
            .bootout(label: .any)
            .willThrow(TestError("launchctl failed"))

        // When / Then
        try await subject.run(fullHandle: "organization/project")
    }
}
