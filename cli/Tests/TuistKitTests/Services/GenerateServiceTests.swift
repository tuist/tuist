import Foundation
import Mockable
import Path
import Testing
import TuistCache
import TuistCore
import TuistServer
import TuistSupport
import XcodeProj

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
