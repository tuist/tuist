import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCache
import TuistConfig
import TuistCore
import TuistGenerator
import TuistOpener
import TuistServer
import TuistSupport
import XcodeProj

@testable import TuistConfigLoader
@testable import TuistKit
@testable import TuistLoader
@testable import TuistTesting

struct GenerateServiceTests {
    private var subject: GenerateService!
    private var opener: MockOpening!
    private var generator: MockGenerating!
    private var generatorFactory: MockGeneratorFactorying!
    private var cacheStorageFactory: MockCacheStorageFactorying!
    private var clock: StubClock!
    private var configLoader: MockConfigLoading!

    init() {
        opener = .init()
        generator = .init()
        generatorFactory = .init()
        configLoader = .init()
        given(generatorFactory)
            .generation(
                config: .any,
                includedTargets: .any,
                configuration: .any,
                cacheProfile: .any,
                cacheStorage: .any
            )
            .willReturn(generator)
        cacheStorageFactory = .init()
        given(cacheStorageFactory)
            .cacheStorage(config: .any)
            .willReturn(MockCacheStoring())
        clock = StubClock()
        subject = GenerateService(
            cacheStorageFactory: cacheStorageFactory,
            generatorFactory: generatorFactory,
            clock: clock,
            opener: opener,
            configLoader: configLoader
        )
    }

    @Test func throws_when_the_configuration_is_not_for_a_generated_project() async throws {
        given(configLoader).loadConfig(path: .any).willReturn(.test(project: .testXcodeProject()))

        await #expect(
            throws:
            TuistConfigError
                .notAGeneratedProjectNorSwiftPackage(
                    errorMessageOverride:
                    "The 'tuist generate' command is only available for generated projects and Swift packages."
                ),
            performing: {
                try await subject
                    .run(
                        path: nil,
                        includedTargets: [],
                        noOpen: true,
                        configuration: nil,
                        ignoreBinaryCache: false,
                        cacheProfile: nil
                    )
            }
        )
    }

    @Test func run_fatalErrors_when_theworkspaceGenerationFails() async throws {
        let expectedError = NSError.test()
        given(configLoader).loadConfig(path: .any).willReturn(
            .test(project: .testGeneratedProject())
        )
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willThrow(expectedError)

        await #expect(
            throws: Error.self,
            performing: {
                try await subject
                    .run(
                        path: nil,
                        includedTargets: [],
                        noOpen: true,
                        configuration: nil,
                        ignoreBinaryCache: false,
                        cacheProfile: nil
                    )
            }
        )
    }

    @Test func test_run() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/test.xcworkspace")
        let environment = MapperEnvironment()
        given(configLoader).loadConfig(path: .any).willReturn(
            .test(project: .testGeneratedProject())
        )
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willReturn(
                (
                    workspacePath,
                    .test(),
                    environment
                )
            )

        given(opener)
            .open(path: .any)
            .willReturn()

        // When
        try await subject.run(
            path: nil,
            includedTargets: [],
            noOpen: false,
            configuration: nil,
            ignoreBinaryCache: false,
            cacheProfile: nil
        )

        // Then
        verify(opener)
            .open(path: .value(workspacePath))
            .called(1)
    }

    @Test func run_timeIsPrinted() async throws {
        try await withMockedDependencies {
            // Given
            let workspacePath = try AbsolutePath(validating: "/test.xcworkspace")

            given(configLoader).loadConfig(path: .any).willReturn(
                .test(project: .testGeneratedProject())
            )

            given(opener)
                .open(path: .any)
                .willReturn()

            given(generator)
                .generateWithGraph(path: .any, options: .any)
                .willReturn((workspacePath, .test(), MapperEnvironment()))
            clock.assertOnUnexpectedCalls = true
            clock.primedTimers = [
                0.234,
            ]

            // When
            try await subject.run(
                path: nil,
                includedTargets: [],
                noOpen: false,
                configuration: nil,
                ignoreBinaryCache: false,
                cacheProfile: nil
            )

            // Then
            try TuistTest.expectLogs("Total time taken: 0.234s")
        }
    }

    @Test func passes_allPossible_when_targets_focused_overrides_explicit_profile() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/test.xcworkspace")
        let environment = MapperEnvironment()
        given(configLoader).loadConfig(path: .any).willReturn(
            .test(project: .testGeneratedProject())
        )
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willReturn(
                (
                    workspacePath,
                    .test(),
                    environment
                )
            )

        // When
        try await subject.run(
            path: nil,
            includedTargets: ["App"],
            noOpen: true,
            configuration: nil,
            ignoreBinaryCache: false,
            cacheProfile: .none
        )

        // Then
        verify(generatorFactory)
            .generation(
                config: .any,
                includedTargets: .value(["App"]),
                configuration: .any,
                cacheProfile: .matching { $0 == .allPossible },
                cacheStorage: .any
            )
            .called(1)
    }

    @Test func passes_explicit_builtin_profile_all_possible() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/test.xcworkspace")
        let environment = MapperEnvironment()
        given(configLoader).loadConfig(path: .any).willReturn(
            .test(project: .testGeneratedProject())
        )
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willReturn(
                (
                    workspacePath,
                    .test(),
                    environment
                )
            )

        // When
        try await subject.run(
            path: nil,
            includedTargets: [],
            noOpen: true,
            configuration: nil,
            ignoreBinaryCache: false,
            cacheProfile: .allPossible
        )

        // Then
        verify(generatorFactory)
            .generation(
                config: .any,
                includedTargets: .value([]),
                configuration: .any,
                cacheProfile: .matching { $0 == .allPossible },
                cacheStorage: .any
            )
            .called(1)
    }

    @Test func passes_none_when_no_binary_cache_flag() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/test.xcworkspace")
        let environment = MapperEnvironment()
        given(configLoader).loadConfig(path: .any).willReturn(
            .test(project: .testGeneratedProject())
        )
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willReturn(
                (
                    workspacePath,
                    .test(),
                    environment
                )
            )

        // When
        try await subject.run(
            path: nil,
            includedTargets: [],
            noOpen: true,
            configuration: nil,
            ignoreBinaryCache: true,
            cacheProfile: nil
        )

        // Then
        verify(generatorFactory)
            .generation(
                config: .any,
                includedTargets: .value([]),
                configuration: .any,
                cacheProfile: .matching { $0 == .none },
                cacheStorage: .any
            )
            .called(1)
    }

    @Test func passes_config_default_custom_when_no_flag_and_no_focus() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/test.xcworkspace")
        let environment = MapperEnvironment()
        let tuist = Tuist.test(project:
            .generated(.test(cacheOptions: .test(
                keepSourceTargets: false,
                profiles: .init(
                    [
                        "ci": .init(base: .onlyExternal, targetQueries: ["tag:cacheable"]),
                    ],
                    default: "ci"
                )
            )))
        )
        given(configLoader).loadConfig(path: .any).willReturn(tuist)
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willReturn(
                (
                    workspacePath,
                    .test(),
                    environment
                )
            )

        // When
        try await subject.run(
            path: nil,
            includedTargets: [],
            noOpen: true,
            configuration: nil,
            ignoreBinaryCache: false,
            cacheProfile: nil
        )

        // Then
        verify(generatorFactory)
            .generation(
                config: .any,
                includedTargets: .value([]),
                configuration: .any,
                cacheProfile: .matching { $0 == .init(base: .onlyExternal, targetQueries: ["tag:cacheable"]) },
                cacheStorage: .any
            )
            .called(1)
    }

    @Test func user_facing_error_when_default_custom_missing_from_cli_path() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willThrow(CacheOptionsManifestMapperError.defaultCacheProfileNotFound(profile: "missing", available: []))

        // When / Then
        await #expect(throws: CacheOptionsManifestMapperError.defaultCacheProfileNotFound(profile: "missing", available: [])) {
            try await subject.run(
                path: nil,
                includedTargets: [],
                noOpen: true,
                configuration: nil,
                ignoreBinaryCache: false,
                cacheProfile: nil
            )
        }
    }

    @Test func throws_when_explicit_custom_profile_missing() async throws {
        // Given
        given(configLoader).loadConfig(path: .any).willReturn(
            .test(project: .testGeneratedProject())
        )

        // When / Then
        await #expect(throws: CacheProfileError.profileNotFound(profile: "missing", available: [])) {
            try await subject.run(
                path: nil,
                includedTargets: [],
                noOpen: true,
                configuration: nil,
                ignoreBinaryCache: false,
                cacheProfile: "missing"
            )
        }
    }
}

@Suite(.serialized)
struct GenerateServiceAutoInstallTests {
    private let fileSystem = FileSystem()
    private var subject: GenerateService!
    private var generator: MockGenerating!
    private var generatorFactory: MockGeneratorFactorying!
    private var cacheStorageFactory: MockCacheStorageFactorying!
    private var configLoader: MockConfigLoading!
    private var installService: MockInstallServicing!
    private var manifestFilesLocator: MockManifestFilesLocating!

    init() {
        generator = .init()
        generatorFactory = .init()
        cacheStorageFactory = .init()
        configLoader = .init()
        installService = .init()
        manifestFilesLocator = .init()

        given(generatorFactory)
            .generation(
                config: .any,
                includedTargets: .any,
                configuration: .any,
                cacheProfile: .any,
                cacheStorage: .any
            )
            .willReturn(generator)
        given(cacheStorageFactory)
            .cacheStorage(config: .any)
            .willReturn(MockCacheStoring())

        subject = GenerateService(
            cacheStorageFactory: cacheStorageFactory,
            generatorFactory: generatorFactory,
            configLoader: configLoader,
            installService: installService,
            manifestFilesLocator: manifestFilesLocator,
            fileSystem: fileSystem
        )
    }

    @Test(.inTemporaryDirectory)
    func runs_install_when_auto_install_enabled_and_dependencies_are_outdated() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let packageManifestPath = temporaryDirectory.appending(components: ["Tuist", "Package.swift"])
        try await fileSystem.makeDirectory(at: packageManifestPath.parentDirectory)
        try await fileSystem.touch(packageManifestPath)
        try await fileSystem.writeText(
            "current",
            at: packageManifestPath.parentDirectory.appending(component: "Package.resolved")
        )

        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(packageManifestPath)

        let workspacePath = temporaryDirectory.appending(component: "test.xcworkspace")
        given(configLoader).loadConfig(path: .any).willReturn(
            .test(project: .generated(.test(generationOptions: .test(autoInstallOutdatedDependencies: true))))
        )
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willReturn((workspacePath, .test(), MapperEnvironment()))
        given(installService)
            .run(path: .any, update: .any, passthroughArguments: .any)
            .willReturn()

        // When
        try await subject.run(
            path: temporaryDirectory.pathString,
            includedTargets: [],
            noOpen: true,
            configuration: nil,
            ignoreBinaryCache: false,
            cacheProfile: nil
        )

        // Then
        verify(installService)
            .run(path: .any, update: .value(false), passthroughArguments: .value([]))
            .called(1)
    }

    @Test(.inTemporaryDirectory)
    func does_not_run_install_when_auto_install_disabled() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let packageManifestPath = temporaryDirectory.appending(components: ["Tuist", "Package.swift"])
        try await fileSystem.makeDirectory(at: packageManifestPath.parentDirectory)
        try await fileSystem.touch(packageManifestPath)
        try await fileSystem.writeText(
            "current",
            at: packageManifestPath.parentDirectory.appending(component: "Package.resolved")
        )

        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(packageManifestPath)

        let workspacePath = temporaryDirectory.appending(component: "test.xcworkspace")
        given(configLoader).loadConfig(path: .any).willReturn(
            .test(project: .generated(.test(generationOptions: .test(autoInstallOutdatedDependencies: false))))
        )
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willReturn((workspacePath, .test(), MapperEnvironment()))

        // When
        try await subject.run(
            path: temporaryDirectory.pathString,
            includedTargets: [],
            noOpen: true,
            configuration: nil,
            ignoreBinaryCache: false,
            cacheProfile: nil
        )

        // Then
        verify(installService)
            .run(path: .any, update: .any, passthroughArguments: .any)
            .called(0)
    }

    @Test(.inTemporaryDirectory)
    func does_not_run_install_when_dependencies_are_up_to_date() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let packageDirectory = temporaryDirectory.appending(component: "Tuist")
        let packageManifestPath = packageDirectory.appending(component: "Package.swift")
        try await fileSystem.makeDirectory(at: packageDirectory)
        try await fileSystem.touch(packageManifestPath)
        let currentResolved = packageDirectory.appending(component: "Package.resolved")
        let savedResolved = packageDirectory.appending(components: [".build", "Derived", "Package.resolved"])
        try await fileSystem.writeText("resolved", at: currentResolved)
        try await fileSystem.makeDirectory(at: savedResolved.parentDirectory)
        try await fileSystem.writeText("resolved", at: savedResolved)

        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(packageManifestPath)

        let workspacePath = temporaryDirectory.appending(component: "test.xcworkspace")
        given(configLoader).loadConfig(path: .any).willReturn(
            .test(project: .generated(.test(generationOptions: .test(autoInstallOutdatedDependencies: true))))
        )
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willReturn((workspacePath, .test(), MapperEnvironment()))

        // When
        try await subject.run(
            path: temporaryDirectory.pathString,
            includedTargets: [],
            noOpen: true,
            configuration: nil,
            ignoreBinaryCache: false,
            cacheProfile: nil
        )

        // Then
        verify(installService)
            .run(path: .any, update: .any, passthroughArguments: .any)
            .called(0)
    }
}
