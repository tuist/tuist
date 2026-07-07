import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistConfig
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistSupport
import TuistTesting
import XcodeGraph
@testable import TuistGenerator

struct XcodeCacheSettingsProjectMapperTests {
    @Test(.inTemporaryDirectory)
    func map_whenCachingDisabled_returnsUnmodifiedProject() async throws {
        // Given
        let tuist = Tuist(
            project: .generated(
                .test(
                    generationOptions: .test(enableCaching: false)
                )
            ),
            fullHandle: "test/handle",
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: Constants.URLs.production
        )
        let subject = XcodeCacheSettingsProjectMapper(tuist: tuist)
        let project = Project.test(
            name: "TestProject",
            settings: .test(
                base: ["EXISTING_SETTING": .string("value")],
                configurations: [.debug: nil, .release: nil]
            )
        )

        // When
        let (mappedProject, sideEffects) = try await subject.map(project: project)

        // Then
        #expect(mappedProject == project)
        #expect(sideEffects.isEmpty)
    }

    @Test(.inTemporaryDirectory)
    func map_whenFullHandleNil_addsLocalCacheSettingsOnly() async throws {
        // Given
        let tuist = Tuist(
            project: .generated(
                .test(
                    generationOptions: .test(enableCaching: true)
                )
            ),
            fullHandle: nil,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: Constants.URLs.production
        )
        let subject = XcodeCacheSettingsProjectMapper(tuist: tuist)
        let project = Project.test(
            name: "TestProject",
            settings: .test(
                base: ["EXISTING_SETTING": .string("value")]
            )
        )

        // When
        let (mappedProject, sideEffects) = try await subject.map(project: project)

        // Then
        #expect(sideEffects.isEmpty)

        let baseSettings = mappedProject.settings.base
        #expect(baseSettings["EXISTING_SETTING"] == .string("value"))

        // Local CAS settings should be present
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_CACHING"] == .string("YES"))

        // Remote caching settings should NOT be present (no fullHandle)
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS"] == nil)
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_PLUGIN"] == nil)
        #expect(baseSettings["COMPILATION_CACHE_REMOTE_SERVICE_PATH"] == nil)
    }

    @Test(.inTemporaryDirectory)
    func map_whenCachingEnabled_addsCacheSettings() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let casPluginPath = temporaryDirectory.appending(component: "libtuist_cas_plugin.dylib")
        try await FileSystem().touch(casPluginPath)
        let fullHandle = "test-org/test-project"
        let tuist = Tuist(
            project: .generated(
                .test(
                    generationOptions: .test(enableCaching: true)
                )
            ),
            fullHandle: fullHandle,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: Constants.URLs.production
        )
        let subject = XcodeCacheSettingsProjectMapper(
            tuist: tuist,
            kuraEnabled: true,
            casPluginCandidates: [casPluginPath]
        )
        let project = Project.test(
            name: "TestProject",
            settings: .test(
                base: ["EXISTING_SETTING": .string("value")],
                configurations: [.debug: nil, .release: nil]
            )
        )

        // When
        let (mappedProject, sideEffects) = try await subject.map(project: project)

        // Then
        #expect(sideEffects.isEmpty)

        let baseSettings = mappedProject.settings.base
        #expect(baseSettings["EXISTING_SETTING"] == .string("value"))

        // Local CAS settings
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_CACHING"] == .string("YES"))

        // Remote caching settings (since fullHandle is provided)
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS"] == .string("YES"))
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_PLUGIN"] == .string("YES"))
        #expect(baseSettings["COMPILATION_CACHE_PLUGIN_PATH"] == .string(casPluginPath.pathString))
        #expect(baseSettings["COMPILATION_CACHE_REMOTE_SERVICE_PATH"] == nil)

        // The account/project is delivered to the plugin as a compiler option so
        // it reaches every frontend, including Xcode ⌘B builds.
        #expect(
            baseSettings["OTHER_SWIFT_FLAGS"]
                == .array(["$(inherited)", "-cas-plugin-option", "tuist-instance=test-org/test-project"])
        )

        #expect(mappedProject.settings.configurations == project.settings.configurations)
    }

    @Test(.inTemporaryDirectory)
    func map_whenPluginMissing_addsLocalCacheSettingsOnly() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let missingPluginPath = temporaryDirectory.appending(component: "libtuist_cas_plugin.dylib")
        let tuist = Tuist(
            project: .generated(
                .test(
                    generationOptions: .test(enableCaching: true)
                )
            ),
            fullHandle: "test-org/test-project",
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: Constants.URLs.production
        )
        let subject = XcodeCacheSettingsProjectMapper(
            tuist: tuist,
            kuraEnabled: true,
            casPluginCandidates: [missingPluginPath]
        )
        let project = Project.test(name: "TestProject", settings: .test(base: [:]))

        // When
        let (mappedProject, _) = try await subject.map(project: project)

        // Then: local caching on, but no plugin settings since the dylib is absent
        let baseSettings = mappedProject.settings.base
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_CACHING"] == .string("YES"))
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_PLUGIN"] == nil)
        #expect(baseSettings["COMPILATION_CACHE_PLUGIN_PATH"] == nil)
        #expect(baseSettings["OTHER_SWIFT_FLAGS"] == nil)
    }

    @Test(.inTemporaryDirectory)
    func map_whenNoExistingSettings_addsOnlyCacheSettings() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let casPluginPath = temporaryDirectory.appending(component: "libtuist_cas_plugin.dylib")
        try await FileSystem().touch(casPluginPath)
        let fullHandle = "org/project"
        let tuist = Tuist(
            project: .generated(
                .test(
                    generationOptions: .test(enableCaching: true)
                )
            ),
            fullHandle: fullHandle,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: Constants.URLs.production
        )
        let subject = XcodeCacheSettingsProjectMapper(
            tuist: tuist,
            kuraEnabled: true,
            casPluginCandidates: [casPluginPath]
        )
        let project = Project.test(
            name: "TestProject",
            settings: .test(base: [:])
        )

        // When
        let (mappedProject, sideEffects) = try await subject.map(project: project)

        // Then
        #expect(sideEffects.isEmpty)

        let baseSettings = mappedProject.settings.base

        // Local CAS settings
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_CACHING"] == .string("YES"))

        // Remote caching settings (since fullHandle is provided)
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS"] == .string("YES"))
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_PLUGIN"] == .string("YES"))
        #expect(baseSettings["COMPILATION_CACHE_PLUGIN_PATH"] == .string(casPluginPath.pathString))
        #expect(baseSettings["COMPILATION_CACHE_REMOTE_SERVICE_PATH"] == nil)
    }

    @Test(.inTemporaryDirectory)
    func map_preservesOtherProjectProperties() async throws {
        // Given
        let fullHandle = "test/handle"
        let tuist = Tuist(
            project: .generated(
                .test(
                    generationOptions: .test(enableCaching: true)
                )
            ),
            fullHandle: fullHandle,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: Constants.URLs.production
        )
        let subject = XcodeCacheSettingsProjectMapper(tuist: tuist)

        let targets = [
            Target.test(name: "App", product: .app),
            Target.test(name: "Framework", product: .framework),
        ]

        let project = Project.test(
            path: "/path/to/project",
            name: "ComplexProject",
            settings: .test(
                base: ["CUSTOM": .string("value")],
                configurations: [
                    .debug: Configuration.test(),
                    .release: Configuration.test(),
                ]
            ),
            targets: targets
        )

        // When
        let (mappedProject, _) = try await subject.map(project: project)

        // Then
        #expect(mappedProject.settings.base["CUSTOM"] == .string("value"))
        #expect(mappedProject.settings.base["COMPILATION_CACHE_ENABLE_CACHING"] == .string("YES"))
    }

    @Test(.inTemporaryDirectory)
    func map_whenKuraDisabled_addsLegacyRemoteServiceSettings() async throws {
        // Given: no kura flag → the legacy per-project daemon path
        let fullHandle = "test-org/test-project"
        let tuist = Tuist(
            project: .generated(
                .test(
                    generationOptions: .test(enableCaching: true)
                )
            ),
            fullHandle: fullHandle,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: Constants.URLs.production
        )
        let subject = XcodeCacheSettingsProjectMapper(tuist: tuist, kuraEnabled: false)
        let project = Project.test(name: "TestProject", settings: .test(base: [:]))

        // When
        let (mappedProject, _) = try await subject.map(project: project)

        // Then: Xcode's built-in remote-cache service (daemon socket), not the plugin
        let baseSettings = mappedProject.settings.base
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_CACHING"] == .string("YES"))
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_PLUGIN"] == .string("YES"))
        #expect(
            baseSettings["COMPILATION_CACHE_REMOTE_SERVICE_PATH"]
                == .string(Environment.current.cacheSocketPathString(for: fullHandle))
        )
        #expect(baseSettings["COMPILATION_CACHE_PLUGIN_PATH"] == nil)
        #expect(baseSettings["OTHER_SWIFT_FLAGS"] == nil)
    }
}
