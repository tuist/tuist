import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistLaunchctl
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

struct SetupCacheCommandServiceTests {
    private let subject: SetupCacheCommandService
    private let fileSystem = FileSystem()
    private let launchctlController = MockLaunchctlControlling()
    private let configLoader = MockConfigLoading()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let manifestLoader = MockManifestLoading()

    init() {
        subject = SetupCacheCommandService(
            fileSystem: fileSystem,
            launchctlController: launchctlController,
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
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment(), .withMockedLogger()) func setupCache_withTuistProject() async throws {
        // Given
        _ = try #require(FileSystem.temporaryTestDirectory)
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

        given(launchctlController)
            .load(plistPath: .any)
            .willReturn()

        // When
        try await subject.run(path: nil)

        // Then
        let homeDirectory = Environment.current.homeDirectory
        let expectedPlistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.cache.organization_project.plist"
        )

        verify(launchctlController)
            .load(plistPath: .value(expectedPlistPath))
            .called(1)

        let plistContent = try await fileSystem.readTextFile(at: expectedPlistPath)
        #expect(plistContent.contains("<string>tuist.cache.organization_project</string>"))

        TuistTest.expectLogs("Xcode Cache has been enabled 🎉")
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

        given(launchctlController)
            .load(plistPath: .any)
            .willReturn()

        // When
        try await subject.run(path: nil)

        // Then
        verify(launchctlController)
            .load(plistPath: .any)
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

        given(launchctlController)
            .load(plistPath: .any)
            .willReturn()

        // When
        try await subject.run(path: nil)

        // Then
        let homeDirectory = Environment.current.homeDirectory
        let expectedPlistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.cache.organization_project.plist"
        )
        let plistContent = try await fileSystem.readTextFile(at: expectedPlistPath)
        #expect(plistContent.contains("--url"))
        #expect(plistContent.contains("https://custom.tuist.dev"))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func setupCache_unloadsExistingAgent() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        let config = Tuist.test(fullHandle: "organization/project")
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        let homeDirectory = Environment.current.homeDirectory
        let expectedPlistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.cache.organization_project.plist"
        )

        try await fileSystem.makeDirectory(at: expectedPlistPath.parentDirectory)
        try await fileSystem.writeText("existing plist content", at: expectedPlistPath)

        given(launchctlController)
            .unload(plistPath: .value(expectedPlistPath))
            .willReturn()

        given(launchctlController)
            .load(plistPath: .any)
            .willReturn()

        // When
        try await subject.run(path: nil)

        // Then
        verify(launchctlController)
            .unload(plistPath: .value(expectedPlistPath))
            .called(1)

        verify(launchctlController)
            .load(plistPath: .value(expectedPlistPath))
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func setupCache_miseManaged() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        let currentMisePath = temporaryDirectory.appending(
            components: ".local", "share", "mise", "installs", "tuist", "4.0.0", "bin", "tuist"
        )
        environment.homeDirectory = temporaryDirectory
        environment.currentExecutablePathStub = currentMisePath

        let expectedBinaryPath = temporaryDirectory.appending(
            components: ".local", "share", "mise", "installs", "tuist", "latest", "tuist"
        )
        try await fileSystem.makeDirectory(at: expectedBinaryPath.parentDirectory)
        try await fileSystem.writeText("", at: expectedBinaryPath)

        let config = Tuist.test(fullHandle: "organization/project")
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        given(launchctlController)
            .load(plistPath: .any)
            .willReturn()

        // When
        try await subject.run(path: nil)

        // Then
        let homeDirectory = Environment.current.homeDirectory
        let expectedPlistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.cache.organization_project.plist"
        )
        let plistContent = try await fileSystem.readTextFile(at: expectedPlistPath)
        #expect(plistContent.contains(expectedBinaryPath.pathString.replacingOccurrences(of: "/private", with: "")))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func setupCache_miseManagedOldPath() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        let currentMisePath = temporaryDirectory.appending(
            components: ".local", "share", "mise", "installs", "tuist", "4.0.0", "bin", "tuist"
        )
        environment.homeDirectory = temporaryDirectory
        environment.currentExecutablePathStub = currentMisePath

        let expectedBinaryPath = temporaryDirectory.appending(
            components: ".local", "share", "mise", "installs", "tuist", "latest", "bin", "tuist"
        )
        try await fileSystem.makeDirectory(at: expectedBinaryPath.parentDirectory)
        try await fileSystem.writeText("", at: expectedBinaryPath)

        let config = Tuist.test(fullHandle: "organization/project")
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        given(launchctlController)
            .load(plistPath: .any)
            .willReturn()

        // When
        try await subject.run(path: nil)

        // Then
        let homeDirectory = Environment.current.homeDirectory
        let expectedPlistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.cache.organization_project.plist"
        )
        let plistContent = try await fileSystem.readTextFile(at: expectedPlistPath)
        #expect(plistContent.contains(expectedBinaryPath.pathString.replacingOccurrences(of: "/private", with: "")))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func setupCache_miseManagedFallbackToCurrentPath() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        let currentMisePath = temporaryDirectory.appending(
            components: ".local", "share", "mise", "installs", "tuist", "4.0.0", "bin", "tuist"
        )
        environment.homeDirectory = temporaryDirectory
        environment.currentExecutablePathStub = currentMisePath

        let config = Tuist.test(fullHandle: "organization/project")
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        given(launchctlController)
            .load(plistPath: .any)
            .willReturn()

        // When
        try await subject.run(path: nil)

        // Then
        let homeDirectory = Environment.current.homeDirectory
        let expectedPlistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.cache.organization_project.plist"
        )
        let plistContent = try await fileSystem.readTextFile(at: expectedPlistPath)
        #expect(plistContent.contains(currentMisePath.pathString.replacingOccurrences(of: "/private", with: "")))
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

    @Test(.withMockedEnvironment()) func setupCache_missingExecutablePath() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = nil

        // When/Then
        await #expect(throws: SetupCacheCommandServiceError.missingExecutablePath) {
            try await subject.run(path: nil)
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func setupCache_launchDaemonLoadFailure() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        let config = Tuist.test(fullHandle: "organization/project")
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        given(launchctlController)
            .load(plistPath: .any)
            .willThrow(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Load failed"]))

        // When/Then
        await #expect(throws: SetupCacheCommandServiceError.failedToLoadLaunchDaemon("Load failed")) {
            try await subject.run(path: nil)
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func setupCache_createsLaunchAgentsDirectory() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        let config = Tuist.test(fullHandle: "organization/project")
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        given(launchctlController)
            .load(plistPath: .any)
            .willReturn()

        // When
        try await subject.run(path: nil)

        // Then
        let homeDirectory = Environment.current.homeDirectory
        let launchAgentsDir = homeDirectory.appending(components: "Library", "LaunchAgents")
        #expect(try await fileSystem.exists(launchAgentsDir))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func setupCache_includesEnvironmentTokenInPlist() async throws {
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

        given(launchctlController)
            .load(plistPath: .any)
            .willReturn()

        // When
        try await subject.run(path: nil)

        // Then
        let homeDirectory = Environment.current.homeDirectory
        let expectedPlistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.cache.organization_project.plist"
        )

        let plistContent = try await fileSystem.readTextFile(at: expectedPlistPath)
        #expect(plistContent.contains("<key>EnvironmentVariables</key>"))
        #expect(plistContent.contains("<key>TUIST_TOKEN</key>"))
        #expect(plistContent.contains("<string>\(token)</string>"))
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

        given(launchctlController)
            .load(plistPath: .any)
            .willReturn()

        // When
        try await subject.run(path: nil)

        // Then
        let homeDirectory = Environment.current.homeDirectory
        let expectedPlistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.cache.organization_project.plist"
        )

        let plistContent = try await fileSystem.readTextFile(at: expectedPlistPath)
        #expect(!plistContent.contains("<key>EnvironmentVariables</key>"))
        #expect(!plistContent.contains("<key>TUIST_CONFIG_TOKEN</key>"))
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

        given(launchctlController)
            .load(plistPath: .any)
            .willReturn()

        // When
        try await subject.run(path: nil)

        // Then
        verify(launchctlController)
            .load(plistPath: .any)
            .called(1)

        TuistTest.expectLogs("Xcode Cache setup is almost complete!")
        TuistTest
            .expectLogs("To enable Xcode Cache for this project, set the enableCaching property in your Tuist.swift file to true:"
            )
    }
}
