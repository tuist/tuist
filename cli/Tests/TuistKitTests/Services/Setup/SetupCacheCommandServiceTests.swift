import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistAlert
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
    private let serverAuthenticationController = MockServerAuthenticationControlling()
    private let manifestLoader = MockManifestLoading()

    init() {
        subject = SetupCacheCommandService(
            launchAgentService: launchAgentService,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            serverAuthenticationController: serverAuthenticationController,
            manifestLoader: manifestLoader
        )

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(Constants.URLs.production)

        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(false)

        given(launchAgentService)
            .setupLaunchAgent(label: .any, plistFileName: .any, programArguments: .any, environmentVariables: .any)
            .willReturn()

        given(launchAgentService)
            .teardownLaunchAgent(label: .any, plistFileName: .any)
            .willReturn()
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment(), .withMockedLogger()) func setupCache_withTuistProject() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")
        environment.variables["TUIST_FEATURE_FLAG_KURA"] = "1"

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

        let alertController = AlertController()

        // When
        try await AlertController.$current.withValue(alertController) {
            try await subject.run(path: nil)
        }

        // Then
        verify(launchAgentService)
            .setupLaunchAgent(
                label: .value("tuist.cas-proxy"),
                plistFileName: .value("tuist.cas-proxy.plist"),
                programArguments: .any,
                environmentVariables: .any
            )
            .called(1)

        let success = try #require(alertController.success().last)
        #expect(success.message.plain().contains("Xcode Cache has been enabled 🎉"))
        #expect(success.takeaways.contains { $0.plain().contains("Xcode Cache is set up") })
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(),
        .withMockedLogger()
    ) func setupCache_withNonTuistProject() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")
        environment.variables["TUIST_FEATURE_FLAG_KURA"] = "1"

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
        TuistTest.expectLogs("COMPILATION_CACHE_PLUGIN_PATH=")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func setupCache_withCustomURL() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")
        environment.variables["TUIST_FEATURE_FLAG_KURA"] = "1"

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
        environment.variables["TUIST_FEATURE_FLAG_KURA"] = "1"

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
                label: .value("tuist.cas-proxy"),
                plistFileName: .value("tuist.cas-proxy.plist"),
                programArguments: .any,
                environmentVariables: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment()) func setupCache_missingFullHandle() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")
        environment.variables["TUIST_FEATURE_FLAG_KURA"] = "1"

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

    @Test(.withMockedEnvironment()) func setupCache_notAuthenticated() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")
        environment.variables["TUIST_FEATURE_FLAG_KURA"] = "1"

        serverAuthenticationController.reset()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(nil)

        // When/Then: setup must fail fast rather than installing a LaunchAgent whose
        // daemon would immediately exit because there are no credentials.
        await #expect(throws: SetupCacheCommandServiceError.notAuthenticated) {
            try await subject.run(path: nil)
        }

        verify(launchAgentService)
            .setupLaunchAgent(label: .any, plistFileName: .any, programArguments: .any, environmentVariables: .any)
            .called(0)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func setupCache_includesEnvironmentToken() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")
        environment.variables["TUIST_FEATURE_FLAG_KURA"] = "1"
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
                environmentVariables: .value([
                    "TUIST_CAS_TOKEN": token,
                    "TUIST_TOKEN": token,
                    "TUIST_FEATURE_FLAG_KURA": "1",
                ])
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func setupCache_forwardsClientFeatureFlags() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")
        environment.variables["TUIST_FEATURE_FLAG_KURA"] = "1"
        let token = "test-auth-token-123"
        environment.variables[Constants.EnvironmentVariables.token] = token

        let config = Tuist.test(fullHandle: "organization/project")
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        // When
        try await subject.run(path: nil)

        // Then: the launchd agent does not inherit the caller's environment, so
        // the feature flags must be forwarded or the daemon resolves the default
        // (public) cache endpoint instead of the kura private-network one.
        verify(launchAgentService)
            .setupLaunchAgent(
                label: .any,
                plistFileName: .any,
                programArguments: .any,
                environmentVariables: .value([
                    "TUIST_CAS_TOKEN": token,
                    "TUIST_TOKEN": token,
                    "TUIST_FEATURE_FLAG_KURA": "1",
                ])
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func setupCache_forwardsCacheEndpointOverride() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")
        environment.variables["TUIST_FEATURE_FLAG_KURA"] = "1"
        let token = "test-auth-token-123"
        environment.variables[Constants.EnvironmentVariables.token] = token
        environment.variables["TUIST_CACHE_ENDPOINT"] = "http://172.16.0.2:30815"

        let config = Tuist.test(fullHandle: "organization/project")
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        // When
        try await subject.run(path: nil)

        // Then: the runner-cache dispatch sets TUIST_CACHE_ENDPOINT as a hard
        // override, but the launchd agent does not inherit it, so it must be
        // forwarded or the CAS keeps resolving the public endpoint.
        verify(launchAgentService)
            .setupLaunchAgent(
                label: .any,
                plistFileName: .any,
                programArguments: .any,
                environmentVariables: .value([
                    "TUIST_CAS_TOKEN": token,
                    "TUIST_TOKEN": token,
                    "TUIST_FEATURE_FLAG_KURA": "1",
                    "TUIST_CACHE_ENDPOINT": "http://172.16.0.2:30815",
                ])
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
        environment.variables["TUIST_FEATURE_FLAG_KURA"] = "1"
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
                environmentVariables: .value(["TUIST_FEATURE_FLAG_KURA": "1"])
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
        environment.variables["TUIST_FEATURE_FLAG_KURA"] = "1"

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
        TuistTest.expectLogs("Xcode Cache is set up")
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment()
    ) func setupCache_programArgumentsIncludeCacheProxyAndAccount() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")
        environment.variables["TUIST_FEATURE_FLAG_KURA"] = "1"

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
                programArguments: .matching { $0.contains("cache-proxy") && $0.contains("organization") },
                environmentVariables: .any
            )
            .called(1)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(),
        .withMockedLogger()
    ) func setupCache_withoutKuraFlag_installsLegacyDaemon() async throws {
        // Given: no TUIST_FEATURE_FLAG_KURA, so setup takes the legacy per-project
        // daemon path that every not-yet-migrated account still runs. The kura
        // backwards-compat promise rests on this branch, so pin its behaviour.
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")
        let token = "test-auth-token-123"
        environment.variables[Constants.EnvironmentVariables.token] = token

        let config = Tuist.test(
            fullHandle: "organization/project",
            xcodeCache: Tuist.XcodeCache(upload: false)
        )
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)

        // When
        try await subject.run(path: nil)

        // Then: the per-project agent label, `cache-start` args (with --no-upload),
        // and TUIST_TOKEN seeding are all pinned.
        verify(launchAgentService)
            .setupLaunchAgent(
                label: .value("tuist.cache.organization_project"),
                plistFileName: .value("tuist.cache.organization_project.plist"),
                programArguments: .value([
                    "cache-start",
                    "organization/project",
                    "--url",
                    Constants.URLs.production.absoluteString,
                    "--no-upload",
                ]),
                environmentVariables: .value(["TUIST_TOKEN": token])
            )
            .called(1)
    }
}
