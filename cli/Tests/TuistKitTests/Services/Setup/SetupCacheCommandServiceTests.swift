import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistConfig
import TuistConfigLoader
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistLaunchctl
import TuistLoader
import TuistLoggerTesting
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

struct SetupCacheCommandServiceTests {
    private let subject: SetupCacheCommandService
    private let launchAgentService = MockLaunchAgentServicing()
    private let configLoader = MockConfigLoading()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let manifestLoader = MockManifestLoading()

    init() {
        subject = SetupCacheCommandService(
            launchAgentService: launchAgentService,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            manifestLoader: manifestLoader
        )

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(Constants.URLs.production)

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(false)

        given(launchAgentService)
            .setupLaunchAgent(label: .any, plistFileName: .any, programArguments: .any, environmentVariables: .any)
            .willReturn()
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment(), .withMockedLogger()) func setupCache_withTuistProject() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        let config = Tuist.test(
            project: .generated(.test(generationOptions: .test(enableCaching: true))),
            fullHandle: "organization/project"
        )
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        manifestLoader.reset()
        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(true)

        // When
        try await subject.run(path: nil)

        // Then
        verify(launchAgentService)
            .setupLaunchAgent(
                label: .value("tuist.cache.organization_project"),
                plistFileName: .value("tuist.cache.organization_project.plist"),
                programArguments: .any,
                environmentVariables: .any
            )
            .called(1)

        TuistTest.expectLogs("Xcode Cache has been enabled 🎉")
        TuistTest.expectLogs("Xcode talks to the cache daemon over the socket at: ")
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(),
        .withMockedLogger()
    ) func setupCache_withNonTuistProject() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        let config = Tuist.test(fullHandle: "organization/project")
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        // When
        try await subject.run(path: nil)

        // Then
        verify(launchAgentService)
            .setupLaunchAgent(label: .any, plistFileName: .any, programArguments: .any, environmentVariables: .any)
            .called(1)

        TuistTest.expectLogs("Xcode Cache setup is almost complete!")
        TuistTest.expectLogs("COMPILATION_CACHE_REMOTE_SERVICE_PATH=")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func setupCache_withCustomURL() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        let customURL = URL(string: "https://custom.tuist.dev")!
        let config = Tuist.test(
            fullHandle: "organization/project",
            url: customURL
        )
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        serverEnvironmentService.reset()
        given(serverEnvironmentService)
            .url(configServerURL: .value(customURL))
            .willReturn(customURL)

        // When
        try await subject.run(path: nil)

        // Then
        verify(launchAgentService)
            .setupLaunchAgent(
                label: .any,
                plistFileName: .any,
                programArguments: .matching { $0.contains("--url") && $0.contains("https://custom.tuist.dev") },
                environmentVariables: .any
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func setupCache_passesCorrectLabelAndPlistFileName() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        let config = Tuist.test(fullHandle: "organization/project")
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        // When
        try await subject.run(path: nil)

        // Then
        verify(launchAgentService)
            .setupLaunchAgent(
                label: .value("tuist.cache.organization_project"),
                plistFileName: .value("tuist.cache.organization_project.plist"),
                programArguments: .any,
                environmentVariables: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment()) func setupCache_missingFullHandle() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        let config = Tuist.test(fullHandle: nil)
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        // When/Then
        await #expect(throws: SetupCacheCommandServiceError.missingFullHandle) {
            try await subject.run(path: nil)
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func setupCache_includesEnvironmentToken() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")
        let token = "test-auth-token-123"
        environment.variables[Constants.EnvironmentVariables.token] = token

        let config = Tuist.test(fullHandle: "organization/project")
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        // When
        try await subject.run(path: nil)

        // Then
        verify(launchAgentService)
            .setupLaunchAgent(
                label: .any,
                plistFileName: .any,
                programArguments: .any,
                environmentVariables: .value(["TUIST_TOKEN": token])
            )
            .called(1)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment()
    ) func setupCache_doesNotIncludeEnvironmentVariablesWhenNoToken() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")
        environment.variables[Constants.EnvironmentVariables.token] = nil

        let config = Tuist.test(fullHandle: "organization/project")
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        // When
        try await subject.run(path: nil)

        // Then
        verify(launchAgentService)
            .setupLaunchAgent(
                label: .any,
                plistFileName: .any,
                programArguments: .any,
                environmentVariables: .value([:])
            )
            .called(1)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment()
    ) func setupCache_withUploadDisabled_includesNoUploadFlag() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        let config = Tuist.test(
            fullHandle: "organization/project",
            cache: .init(upload: false)
        )
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        // When
        try await subject.run(path: nil)

        // Then
        verify(launchAgentService)
            .setupLaunchAgent(
                label: .any,
                plistFileName: .any,
                programArguments: .matching { $0.contains("--no-upload") },
                environmentVariables: .any
            )
            .called(1)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment()
    ) func setupCache_withUploadEnabled_doesNotIncludeNoUploadFlag() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        let config = Tuist.test(
            fullHandle: "organization/project",
            cache: .init(upload: true)
        )
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        // When
        try await subject.run(path: nil)

        // Then
        verify(launchAgentService)
            .setupLaunchAgent(
                label: .any,
                plistFileName: .any,
                programArguments: .matching { !$0.contains("--no-upload") },
                environmentVariables: .any
            )
            .called(1)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(),
        .withMockedLogger()
    ) func setupCache_withTuistProjectCachingDisabled() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        let config = Tuist.test(
            project: .generated(.test(generationOptions: .test(enableCaching: false))),
            fullHandle: "organization/project"
        )
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        manifestLoader.reset()
        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(true)

        // When
        try await subject.run(path: nil)

        // Then
        verify(launchAgentService)
            .setupLaunchAgent(label: .any, plistFileName: .any, programArguments: .any, environmentVariables: .any)
            .called(1)

        TuistTest.expectLogs("Xcode Cache setup is almost complete!")
        TuistTest
            .expectLogs("To enable Xcode Cache for this project, set the enableCaching property in your Tuist.swift file to true:"
            )
        TuistTest.expectLogs("Xcode talks to the cache daemon over the socket at: ")
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment()
    ) func setupCache_programArgumentsIncludeCacheStartAndFullHandle() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        let config = Tuist.test(fullHandle: "organization/project")
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        // When
        try await subject.run(path: nil)

        // Then
        verify(launchAgentService)
            .setupLaunchAgent(
                label: .any,
                plistFileName: .any,
                programArguments: .matching { $0.contains("cache-start") && $0.contains("organization/project") },
                environmentVariables: .any
            )
            .called(1)
    }
}
