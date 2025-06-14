import Foundation
import Mockable
import Path
import Testing
import TuistCache
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import XcodeProj

@testable import TuistKit
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
                ignoreBinaryCache: .any,
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

    @Test func test_throws_when_the_configuration_is_not_for_a_generated_project() async throws {
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
                        ignoreBinaryCache: false
                    )
            }
        )
    }

    @Test func test_run_fatalErrors_when_theworkspaceGenerationFails() async throws {
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
                        ignoreBinaryCache: false
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
            ignoreBinaryCache: false
        )

        // Then
        verify(opener)
            .open(path: .value(workspacePath))
            .called(1)
    }

    @Test func test_run_timeIsPrinted() async throws {
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
                ignoreBinaryCache: false
            )

            // Then
            try TuistTest.expectLogs("Total time taken: 0.234s")
        }
    }
}
