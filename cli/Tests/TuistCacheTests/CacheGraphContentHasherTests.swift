import Foundation
import Mockable
import Testing
import struct TSCUtility.Version
import TuistCore
import TuistHasher
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistCache

@Suite
struct CacheGraphContentHasherTests {
    private var graphContentHasher: MockGraphContentHashing!
    private var contentHasher: MockContentHashing!
    private var defaultConfigurationFetcher: MockDefaultConfigurationFetching!
    private var subject: CacheGraphContentHasher!

    init() throws {
        graphContentHasher = .init()
        contentHasher = .init()
        defaultConfigurationFetcher = MockDefaultConfigurationFetching()

        subject = CacheGraphContentHasher(
            graphContentHasher: graphContentHasher,
            contentHasher: contentHasher,
            versionFetcher: CacheVersionFetcher(),
            defaultConfigurationFetcher: defaultConfigurationFetcher
        )
    }

    @Test(
        .withMockedSwiftVersionProvider
    ) func contentHashes_when_no_excluded_targets_all_hashes_are_computed() async throws {
        // Given
        let includedTarget = GraphTarget(
            path: "/Project/Path",
            target: Target.test(name: "Included", product: .framework),
            project: Project.test()
        )
        given(graphContentHasher)
            .contentHashes(
                for: .any,
                include: .any,
                destination: .any,
                additionalStrings: .any
            )
            .willReturn([:])
        given(defaultConfigurationFetcher)
            .fetch(configuration: .any, defaultConfiguration: .any, graph: .any)
            .willReturn("Debug")
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock).swiftlangVersion().willReturn("5.10.0")

        // When
        _ = try await subject.contentHashes(
            for: Graph.test(),
            configuration: "Debug",
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )

        // Then
        verify(graphContentHasher)
            .contentHashes(
                for: .any,
                include: .matching { filter in
                    filter(includedTarget)
                },
                destination: .any,
                additionalStrings: .any
            )
            .called(1)
    }

    @Test(
        .withMockedSwiftVersionProvider
    ) func contentHashes_when_excluded_targets_excluded_hashes_are_not_computed() async throws {
        // Given
        let excludedTarget = GraphTarget(
            path: "/Project/Path",
            target: Target.test(name: "Excluded", product: .framework),
            project: Project.test()
        )
        let includedTarget = GraphTarget(
            path: "/Project/Path",
            target: Target.test(name: "Included", product: .framework),
            project: Project.test()
        )
        given(graphContentHasher)
            .contentHashes(
                for: .any,
                include: .any,
                destination: .any,
                additionalStrings: .any
            )
            .willReturn([:])
        given(defaultConfigurationFetcher)
            .fetch(configuration: .any, defaultConfiguration: .any, graph: .any)
            .willReturn("Debug")
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock).swiftlangVersion().willReturn("5.10.0")

        // When
        _ = try await subject.contentHashes(
            for: Graph.test(),
            configuration: "Debug",
            defaultConfiguration: nil,
            excludedTargets: ["Excluded"],
            destination: nil
        )

        // Then
        verify(graphContentHasher)
            .contentHashes(
                for: .any,
                include: .matching { filter in
                    filter(includedTarget) && !filter(excludedTarget)
                },
                destination: .any,
                additionalStrings: .any
            )
            .called(1)
    }

    @Test(
        .withMockedSwiftVersionProvider
    ) func contentHashes_when_excluded_targets_resources_hashes_are_not_computed() async throws {
        // Given
        let project = Project.test()

        let excludedTarget = GraphTarget(
            path: "/Project/Path",
            target: Target.test(name: "Excluded", product: .framework),
            project: project
        )
        let excludedTargetResource = GraphTarget(
            path: "/Project/Path",
            target: Target.test(name: "\(project.name)_Excluded", product: .bundle),
            project: project
        )
        let includedTarget = GraphTarget(
            path: "/Project/Path",
            target: Target.test(name: "Included", product: .framework),
            project: Project.test()
        )
        given(graphContentHasher)
            .contentHashes(
                for: .any,
                include: .any,
                destination: .any,
                additionalStrings: .any
            )
            .willReturn([:])
        given(defaultConfigurationFetcher)
            .fetch(configuration: .any, defaultConfiguration: .any, graph: .any)
            .willReturn("Debug")
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock).swiftlangVersion().willReturn("5.10.0")

        // When
        _ = try await subject.contentHashes(
            for: Graph.test(),
            configuration: "Debug",
            defaultConfiguration: nil,
            excludedTargets: ["Excluded"],
            destination: nil
        )

        // Then
        verify(graphContentHasher)
            .contentHashes(
                for: .any,
                include: .matching { filter in
                    filter(includedTarget) && !filter(excludedTarget) && !filter(excludedTargetResource)
                },
                destination: .any,
                additionalStrings: .any
            )
            .called(1)
    }
}
