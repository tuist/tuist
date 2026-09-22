import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import struct TSCUtility.Version
import TuistConfig
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting
import TuistSupport
import TuistTesting
import XcodeGraph
@testable import TuistGenerator

struct XcodeCacheSettingsProjectMapperTests {
    /// Stubs the selected Xcode version. Required in every test: the mapper reads the
    /// version to decide whether to enable prefix mapping, and an unstubbed Mockable
    /// call traps rather than throwing.
    private func stubXcodeVersion(_ version: Version) throws {
        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selectedVersion()
            .willReturn(version)
    }

    @Test(.inTemporaryDirectory, .withMockedXcodeController)
    func map_whenCachingDisabled_returnsUnmodifiedProject() async throws {
        // Given
        try stubXcodeVersion(Version(26, 0, 0))
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

    /// Xcode 27 (Swift 6.4) is the first build system that implements the
    /// source/build directory prefix mappings, which make the compilation-cache key
    /// independent of where the project and DerivedData live. Apple ships them off
    /// (no default), so generation opts in.
    @Test(.inTemporaryDirectory, .withMockedXcodeController)
    func map_whenXcode27_enablesPrefixMapping() async throws {
        // Given
        try stubXcodeVersion(Version(27, 0, 0))
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

        // When
        let (mappedProject, _) = try await subject.map(project: Project.test(name: "TestProject"))

        // Then
        let baseSettings = mappedProject.settings.base
        #expect(baseSettings["SWIFT_ENABLE_PREFIX_MAPPING"] == .string("YES"))
        #expect(baseSettings["SWIFT_ENABLE_PROJECT_PREFIX_MAPPING"] == .string("YES"))
        #expect(baseSettings["CLANG_ENABLE_PREFIX_MAPPING"] == .string("YES"))
        #expect(baseSettings["CLANG_ENABLE_PROJECT_PREFIX_MAPPING"] == .string("YES"))
    }

    /// Earlier Xcodes don't define these settings and their build systems lack the
    /// mappings, so setting them would be inert noise in the generated project.
    @Test(.inTemporaryDirectory, .withMockedXcodeController)
    func map_whenXcodeOlderThan27_doesNotEnablePrefixMapping() async throws {
        // Given
        try stubXcodeVersion(Version(26, 5, 0))
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

        // When
        let (mappedProject, _) = try await subject.map(project: Project.test(name: "TestProject"))

        // Then
        let baseSettings = mappedProject.settings.base
        #expect(baseSettings["COMPILATION_CACHE_ENABLE_CACHING"] == .string("YES"))
        #expect(baseSettings["SWIFT_ENABLE_PREFIX_MAPPING"] == nil)
        #expect(baseSettings["SWIFT_ENABLE_PROJECT_PREFIX_MAPPING"] == nil)
        #expect(baseSettings["CLANG_ENABLE_PREFIX_MAPPING"] == nil)
        #expect(baseSettings["CLANG_ENABLE_PROJECT_PREFIX_MAPPING"] == nil)
    }

    @Test(.inTemporaryDirectory, .withMockedXcodeController)
    func map_whenFullHandleNil_addsLocalCacheSettingsOnly() async throws {
        // Given
        try stubXcodeVersion(Version(26, 0, 0))
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

    @Test(.inTemporaryDirectory, .withMockedXcodeController)
    func map_whenCachingEnabled_addsCacheSettings() async throws {
        // Given
        try stubXcodeVersion(Version(26, 0, 0))
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

        // The proxy's socket is what makes C, Objective-C and precompiled modules
        // shareable: the build system only runs its caching for those when a remote
        // service is configured. Without it, only Swift compilations are shared.
        #expect(
            baseSettings["COMPILATION_CACHE_REMOTE_SERVICE_PATH"]
                == .string(Environment.current.casProxySocketPathString())
        )

        // The account/project is delivered to the plugin as a compiler option so
        // it reaches every frontend, including Xcode ⌘B builds.
        #expect(
            baseSettings["OTHER_SWIFT_FLAGS"]
                == .array(["$(inherited)", "-cas-plugin-option", "tuist-instance=test-org/test-project"])
        )

        #expect(mappedProject.settings.configurations == project.settings.configurations)
    }

    @Test(.inTemporaryDirectory, .withMockedXcodeController)
    func map_whenPluginMissing_addsLocalCacheSettingsOnly() async throws {
        // Given
        try stubXcodeVersion(Version(26, 0, 0))
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

    @Test(.inTemporaryDirectory, .withMockedXcodeController)
    func map_whenUploadDisabled_addsUploadOptionToSwiftFlags() async throws {
        // Given
        try stubXcodeVersion(Version(26, 0, 0))
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let casPluginPath = temporaryDirectory.appending(component: "libtuist_cas_plugin.dylib")
        try await FileSystem().touch(casPluginPath)
        let tuist = Tuist(
            project: .generated(
                .test(
                    generationOptions: .test(enableCaching: true)
                )
            ),
            fullHandle: "test-org/test-project",
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            xcodeCache: .init(upload: false),
            url: Constants.URLs.production
        )
        let subject = XcodeCacheSettingsProjectMapper(
            tuist: tuist,
            casPluginCandidates: [casPluginPath]
        )
        let project = Project.test(name: "TestProject", settings: .test(base: [:]))

        // When
        let (mappedProject, _) = try await subject.map(project: project)

        // Then: xcodeCache(upload: false) is carried to the plugin as a per-project
        // option (the machine-wide proxy env can't express a per-project setting).
        #expect(
            mappedProject.settings.base["OTHER_SWIFT_FLAGS"]
                == .array([
                    "$(inherited)",
                    "-cas-plugin-option",
                    "tuist-instance=test-org/test-project",
                    "-cas-plugin-option",
                    "tuist-upload=false",
                ])
        )
    }

    @Test(.inTemporaryDirectory, .withMockedXcodeController)
    func map_whenNoExistingSettings_addsOnlyCacheSettings() async throws {
        // Given
        try stubXcodeVersion(Version(26, 0, 0))
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
        #expect(
            baseSettings["COMPILATION_CACHE_REMOTE_SERVICE_PATH"]
                == .string(Environment.current.casProxySocketPathString())
        )
    }

    @Test(.inTemporaryDirectory, .withMockedXcodeController)
    func map_preservesOtherProjectProperties() async throws {
        // Given
        try stubXcodeVersion(Version(26, 0, 0))
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

    /// A target that overrides `OTHER_SWIFT_FLAGS` without `$(inherited)` shadows the
    /// project-level flags entirely, so `-cas-plugin-option tuist-instance=<handle>` is
    /// never handed to the compiler frontend for that target. With `-cache-compile-job`
    /// + `-cas-path` + `-cas-plugin-path` on the command line but no plugin option,
    /// swift-frontend rejects the invocation with `Cannot setup CAS due to conflicting
    /// '-cas-*' options`. The mapper needs to patch each shadowing target too, mirroring
    /// what `ModuleMapMapper` and `FrameworkSearchPathsGraphMapper` already do.
    @Test(.inTemporaryDirectory, .withMockedXcodeController)
    func map_whenTargetShadowsOtherSwiftFlags_appendsCASPluginOptionsToTarget() async throws {
        // Given
        try stubXcodeVersion(Version(26, 0, 0))
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
            casPluginCandidates: [casPluginPath]
        )
        // A Notification Service Extension–style target: `OTHER_SWIFT_FLAGS` set at the
        // target level with no `$(inherited)`, so it shadows the project base entirely.
        let shadowingTarget = Target.test(
            name: "MigrosNotificationServiceExtension",
            product: .appExtension,
            settings: Settings(
                base: [
                    "OTHER_SWIFT_FLAGS": .array([
                        "-D", "DEBUG",
                        "-Xfrontend", "-warn-long-function-bodies=100",
                    ]),
                ],
                configurations: [.debug: nil, .release: nil]
            )
        )
        let project = Project.test(
            name: "TestProject",
            settings: .test(
                base: [:],
                configurations: [.debug: nil, .release: nil]
            ),
            targets: [shadowingTarget]
        )

        // When
        let (mappedProject, _) = try await subject.map(project: project)

        // Then: the project base still carries the CAS plugin options for targets that
        // don't shadow.
        #expect(
            mappedProject.settings.base["OTHER_SWIFT_FLAGS"]
                == .array(["$(inherited)", "-cas-plugin-option", "tuist-instance=test-org/test-project"])
        )

        // Then: the shadowing target's `OTHER_SWIFT_FLAGS` now also carries the CAS
        // plugin options — its original flags first, `-cas-plugin-option` pairs
        // appended — so `-cas-plugin-option tuist-instance=...` still reaches the
        // compiler frontend and Swift accepts the CAS setup.
        let mappedTarget = try #require(mappedProject.targets["MigrosNotificationServiceExtension"])
        #expect(
            mappedTarget.settings?.base["OTHER_SWIFT_FLAGS"]
                == .array([
                    "-D", "DEBUG",
                    "-Xfrontend", "-warn-long-function-bodies=100",
                    "-cas-plugin-option", "tuist-instance=test-org/test-project",
                ])
        )
    }

    /// A target whose `OTHER_SWIFT_FLAGS` already contains `$(inherited)` picks up the
    /// project-base CAS options for free, so the mapper must NOT add another copy —
    /// duplicated `-cas-plugin-option` pairs would land twice in the swiftc argv.
    @Test(.inTemporaryDirectory, .withMockedXcodeController)
    func map_whenTargetInheritsOtherSwiftFlags_leavesTargetUntouched() async throws {
        // Given
        try stubXcodeVersion(Version(26, 0, 0))
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let casPluginPath = temporaryDirectory.appending(component: "libtuist_cas_plugin.dylib")
        try await FileSystem().touch(casPluginPath)
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
            casPluginCandidates: [casPluginPath]
        )
        let inheritingTarget = Target.test(
            name: "InheritingTarget",
            settings: Settings(
                base: [
                    "OTHER_SWIFT_FLAGS": .array([
                        "$(inherited)",
                        "-Xfrontend", "-warn-long-function-bodies=100",
                    ]),
                ],
                configurations: [.debug: nil, .release: nil]
            )
        )
        let project = Project.test(
            name: "TestProject",
            settings: .test(base: [:], configurations: [.debug: nil, .release: nil]),
            targets: [inheritingTarget]
        )

        // When
        let (mappedProject, _) = try await subject.map(project: project)

        // Then: the target's `OTHER_SWIFT_FLAGS` are unchanged — `$(inherited)` already
        // pulls in the project-base `-cas-plugin-option tuist-instance=...`.
        let mappedTarget = try #require(mappedProject.targets["InheritingTarget"])
        #expect(
            mappedTarget.settings?.base["OTHER_SWIFT_FLAGS"]
                == .array([
                    "$(inherited)",
                    "-Xfrontend", "-warn-long-function-bodies=100",
                ])
        )
    }

    /// Xcode resolves configuration-level keys independently of the target base, so a
    /// per-configuration override of `OTHER_SWIFT_FLAGS` without `$(inherited)` shadows
    /// the base for that configuration too and drops the CAS plugin options for it.
    @Test(.inTemporaryDirectory, .withMockedXcodeController)
    func map_whenConfigurationShadowsOtherSwiftFlags_appendsCASPluginOptionsToConfiguration() async throws {
        // Given
        try stubXcodeVersion(Version(26, 0, 0))
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let casPluginPath = temporaryDirectory.appending(component: "libtuist_cas_plugin.dylib")
        try await FileSystem().touch(casPluginPath)
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
            casPluginCandidates: [casPluginPath]
        )
        let debugConfiguration = Configuration.test(
            settings: ["OTHER_SWIFT_FLAGS": .array(["-D", "DEBUG"])]
        )
        let target = Target.test(
            name: "ConfigOverridingTarget",
            settings: Settings(
                base: [:],
                configurations: [.debug: debugConfiguration, .release: nil]
            )
        )
        let project = Project.test(
            name: "TestProject",
            settings: .test(base: [:], configurations: [.debug: nil, .release: nil]),
            targets: [target]
        )

        // When
        let (mappedProject, _) = try await subject.map(project: project)

        // Then: the shadowing configuration picks up the CAS plugin options.
        let mappedTarget = try #require(mappedProject.targets["ConfigOverridingTarget"])
        let mappedDebug = try #require(mappedTarget.settings?.configurations[.debug] ?? nil)
        #expect(
            mappedDebug.settings["OTHER_SWIFT_FLAGS"]
                == .array([
                    "-D", "DEBUG",
                    "-cas-plugin-option", "tuist-instance=test-org/test-project",
                ])
        )
    }

    /// The plugin path is baked into the generated pbxproj and feeds the target
    /// content hash through the project's base settings, so a raw install path
    /// (Homebrew locally, mise on CI) would give the same code different module
    /// cache keys on different machines. `COMPILATION_CACHE_REMOTE_SERVICE_PATH`
    /// already gets this treatment via `casProxySocketPathString()`.
    @Test(.inTemporaryDirectory, .withMockedXcodeController, .withMockedEnvironment())
    func map_whenPluginIsUnderHome_writesHomeRelativePluginPath() async throws {
        // Given
        try stubXcodeVersion(Version(26, 0, 0))
        let casPluginPath = Environment.current.homeDirectory
            .appending(components: [".local", "share", "mise", "libtuist_cas_plugin.dylib"])
        try await FileSystem().makeDirectory(at: casPluginPath.parentDirectory)
        try await FileSystem().touch(casPluginPath)
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
            casPluginCandidates: [casPluginPath]
        )
        let project = Project.test(name: "TestProject", settings: .test(base: [:]))

        // When
        let (mappedProject, _) = try await subject.map(project: project)

        // Then
        #expect(
            mappedProject.settings.base["COMPILATION_CACHE_PLUGIN_PATH"]
                == .string("$HOME/.local/share/mise/libtuist_cas_plugin.dylib")
        )
    }

    /// The copy `tuist setup cache` installs keeps the same path across Tuist versions,
    /// so it wins over the plugin shipped inside a versioned install.
    @Test(.inTemporaryDirectory, .withMockedXcodeController, .withMockedEnvironment())
    func map_whenSetupInstalledThePlugin_writesTheInstalledPluginPath() async throws {
        // Given
        try stubXcodeVersion(Version(26, 0, 0))
        let installedPluginPath = Environment.current.casPluginInstallPath()
        let shippedPluginPath = Environment.current.homeDirectory
            .appending(components: [
                ".local",
                "share",
                "mise",
                "installs",
                "tuist",
                "4.206.0",
                "bin",
                "libtuist_cas_plugin.dylib",
            ])
        for pluginPath in [installedPluginPath, shippedPluginPath] {
            try await FileSystem().makeDirectory(at: pluginPath.parentDirectory)
            try await FileSystem().touch(pluginPath)
        }
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
            casPluginCandidates: [installedPluginPath, shippedPluginPath]
        )
        let project = Project.test(name: "TestProject", settings: .test(base: [:]))

        // When
        let (mappedProject, _) = try await subject.map(project: project)

        // Then
        #expect(
            mappedProject.settings.base["COMPILATION_CACHE_PLUGIN_PATH"]
                == .string("$HOME/.local/state/tuist/libtuist_cas_plugin.dylib")
        )
    }

    @Test(.inTemporaryDirectory, .withMockedXcodeController, .withMockedEnvironment())
    func map_whenSetupDidNotInstallThePlugin_writesTheShippedPluginPath() async throws {
        // Given
        try stubXcodeVersion(Version(26, 0, 0))
        let installedPluginPath = Environment.current.casPluginInstallPath()
        let shippedPluginPath = Environment.current.homeDirectory
            .appending(components: [
                ".local",
                "share",
                "mise",
                "installs",
                "tuist",
                "4.206.0",
                "bin",
                "libtuist_cas_plugin.dylib",
            ])
        try await FileSystem().makeDirectory(at: shippedPluginPath.parentDirectory)
        try await FileSystem().touch(shippedPluginPath)
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
            casPluginCandidates: [installedPluginPath, shippedPluginPath]
        )
        let project = Project.test(name: "TestProject", settings: .test(base: [:]))

        // When
        let (mappedProject, _) = try await subject.map(project: project)

        // Then
        #expect(
            mappedProject.settings.base["COMPILATION_CACHE_PLUGIN_PATH"]
                == .string("$HOME/.local/share/mise/installs/tuist/4.206.0/bin/libtuist_cas_plugin.dylib")
        )
    }

    /// A sibling directory whose name merely starts with the home directory's is not
    /// under `$HOME`. Comparing the paths as strings would treat `/Users/me-tools` as
    /// living inside `/Users/me` and emit `$HOME-tools/...`, which resolves nowhere.
    @Test(.inTemporaryDirectory, .withMockedXcodeController, .withMockedEnvironment())
    func map_whenPluginIsInHomeSiblingSharingItsPrefix_writesAbsolutePluginPath() async throws {
        // Given
        try stubXcodeVersion(Version(26, 0, 0))
        let homeDirectory = Environment.current.homeDirectory
        let siblingDirectory = homeDirectory.parentDirectory
            .appending(component: homeDirectory.basename + "-tools")
        let casPluginPath = siblingDirectory.appending(component: "libtuist_cas_plugin.dylib")
        try await FileSystem().makeDirectory(at: siblingDirectory)
        try await FileSystem().touch(casPluginPath)
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
            casPluginCandidates: [casPluginPath]
        )
        let project = Project.test(name: "TestProject", settings: .test(base: [:]))

        // When
        let (mappedProject, _) = try await subject.map(project: project)

        // Then
        #expect(
            mappedProject.settings.base["COMPILATION_CACHE_PLUGIN_PATH"]
                == .string(casPluginPath.pathString)
        )
    }

    /// A plugin installed outside `$HOME` (a Homebrew prefix, say) has no `$HOME` to
    /// factor out and must be written verbatim.
    @Test(.inTemporaryDirectory, .withMockedXcodeController, .withMockedEnvironment())
    func map_whenPluginIsOutsideHome_writesAbsolutePluginPath() async throws {
        // Given
        try stubXcodeVersion(Version(26, 0, 0))
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let casPluginPath = temporaryDirectory.appending(component: "libtuist_cas_plugin.dylib")
        try await FileSystem().touch(casPluginPath)
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
            casPluginCandidates: [casPluginPath]
        )
        let project = Project.test(name: "TestProject", settings: .test(base: [:]))

        // When
        let (mappedProject, _) = try await subject.map(project: project)

        // Then
        #expect(
            mappedProject.settings.base["COMPILATION_CACHE_PLUGIN_PATH"]
                == .string(casPluginPath.pathString)
        )
    }
}
