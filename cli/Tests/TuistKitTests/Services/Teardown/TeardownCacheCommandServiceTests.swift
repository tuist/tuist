import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistConfig
import TuistConfigLoader
import TuistEnvironment
import TuistLaunchctl
import TuistLoader
import TuistLoggerTesting
import TuistTesting

@testable import TuistKit

struct TeardownCacheCommandServiceTests {
    private let subject: TeardownCacheCommandService
    private let launchAgentService = MockLaunchAgentServicing()
    private let configLoader = MockConfigLoading()

    init() {
        subject = TeardownCacheCommandService(
            launchAgentService: launchAgentService,
            configLoader: configLoader,
            fileSystem: FileSystem()
        )

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "organization/project"))

        given(launchAgentService)
            .teardownLaunchAgent(label: .any, plistFileName: .any)
            .willReturn()
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment(), .withMockedLogger()) func teardownCache() async throws {
        let environment = try #require(Environment.mocked)
        let plugin = environment.casPluginInstallPath()
        let manifest = plugin.parentDirectory.appending(component: "cas-install.json")
        try await FileSystem().makeDirectory(at: plugin.parentDirectory)
        try await FileSystem().writeText("plugin", at: plugin)
        try await FileSystem().writeText("metadata", at: manifest)

        // When
        try await subject.run(path: nil)

        // Then: both the machine-wide proxy and the per-project daemon agents are torn down.
        verify(launchAgentService)
            .teardownLaunchAgent(
                label: .value("tuist.cas-proxy"),
                plistFileName: .value("tuist.cas-proxy.plist")
            )
            .called(1)
        verify(launchAgentService)
            .teardownLaunchAgent(
                label: .value("tuist.cache.organization_project"),
                plistFileName: .value("tuist.cache.organization_project.plist")
            )
            .called(1)

        #expect(try await !FileSystem().exists(manifest))
        #expect(try await FileSystem().readTextFile(at: plugin) == "plugin")
        TuistTest.expectLogs("Xcode Cache has been torn down 🧹")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func teardownCache_removesSocketFileWhenPresent() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        let socketPath = environment.cacheSocketPath(for: "organization/project")
        let fileSystem = FileSystem()
        try await fileSystem.makeDirectory(at: socketPath.parentDirectory)
        try await fileSystem.writeText("", at: socketPath)

        // When
        try await subject.run(path: nil)

        // Then
        let socketStillExists = try await fileSystem.exists(socketPath)
        #expect(socketStillExists == false)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func teardownCache_keepsMetadataIfRemovingTheAgentFails() async throws {
        let environment = try #require(Environment.mocked)
        let manifest = environment.casPluginInstallPath().parentDirectory.appending(component: "cas-install.json")
        try await FileSystem().makeDirectory(at: manifest.parentDirectory)
        try await FileSystem().writeText("metadata", at: manifest)
        let error = NSError(domain: "test", code: 1)
        launchAgentService.reset()
        given(launchAgentService).teardownLaunchAgent(label: .any, plistFileName: .any).willThrow(error)

        await #expect(throws: error) { try await subject.run(path: nil) }

        #expect(try await FileSystem().readTextFile(at: manifest) == "metadata")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func teardownCache_succeedsWhenSocketFileMissing() async throws {
        // When / Then
        try await subject.run(path: nil)

        verify(launchAgentService)
            .teardownLaunchAgent(
                label: .value("tuist.cas-proxy"),
                plistFileName: .value("tuist.cas-proxy.plist")
            )
            .called(1)
        verify(launchAgentService)
            .teardownLaunchAgent(
                label: .value("tuist.cache.organization_project"),
                plistFileName: .value("tuist.cache.organization_project.plist")
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment(), .withMockedLogger())
    func teardownCache_tearsDownProxyWhenFullHandleMissing() async throws {
        // Given
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(Tuist.test(fullHandle: nil))

        // When: the machine-wide proxy is torn down regardless of fullHandle;
        // only the per-project daemon teardown needs one, so it is skipped here.
        try await subject.run(path: nil)

        // Then: exactly one teardown (the proxy), no per-project daemon teardown.
        verify(launchAgentService)
            .teardownLaunchAgent(
                label: .value("tuist.cas-proxy"),
                plistFileName: .value("tuist.cas-proxy.plist")
            )
            .called(1)
        verify(launchAgentService)
            .teardownLaunchAgent(label: .any, plistFileName: .any)
            .called(1)
    }
}
