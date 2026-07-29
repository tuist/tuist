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
    ) func contentHashes_scopesSettingsToSelectedConfiguration() async throws {
        // Given
        let requestedConfigurationName = "Debug-SharedCache"
        let selectedConfiguration = BuildConfiguration.debug("debug-sharedcache")
        let unrelatedConfiguration = BuildConfiguration.debug("Debug-AppVariant-B")
        let settings = Settings(
            baseDebug: ["ENABLE_TESTING_SEARCH_PATHS": "YES"],
            configurations: [
                selectedConfiguration: Configuration(settings: ["SELECTED": "YES"]),
                unrelatedConfiguration: Configuration(settings: ["UNRELATED": "YES"]),
            ],
            defaultConfiguration: unrelatedConfiguration.name
        )
        let target = Target.test(name: "Framework", product: .framework, settings: settings)
        let project = Project.test(
            path: "/Project/Path",
            settings: settings,
            targets: [target]
        )
        let projectPath = project.path
        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project]
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
            .willReturn(requestedConfigurationName)
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock).swiftlangVersion().willReturn("5.10.0")

        // When
        _ = try await subject.contentHashes(
            for: graph,
            configuration: requestedConfigurationName,
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )

        // Then
        verify(graphContentHasher)
            .contentHashes(
                for: .matching { graph in
                    guard let scopedProject = graph.projects[projectPath],
                          let targetSettings = scopedProject.targets[target.name]?.settings
                    else {
                        return false
                    }
                    return Set(scopedProject.settings.configurations.keys) == [selectedConfiguration]
                        && Set(targetSettings.configurations.keys) == [selectedConfiguration]
                        && scopedProject.settings.baseDebug == settings.baseDebug
                        && targetSettings.baseDebug == settings.baseDebug
                        && scopedProject.settings.defaultConfiguration == nil
                        && targetSettings.defaultConfiguration == nil
                },
                include: .any,
                destination: .any,
                additionalStrings: .any
            )
            .called(1)
    }

    @Test(
        .withMockedSwiftVersionProvider
    ) func contentHashes_scopesSettingsToDefaultConfiguration() async throws {
        // Given
        let defaultConfigurationName = "Debug-SharedCache"
        let selectedConfiguration = BuildConfiguration.debug(defaultConfigurationName)
        let unrelatedConfiguration = BuildConfiguration.debug("Debug-AppVariant-B")
        let settings = Settings(
            configurations: [
                selectedConfiguration: Configuration(settings: ["SELECTED": "YES"]),
                unrelatedConfiguration: Configuration(settings: ["UNRELATED": "YES"]),
            ]
        )
        let target = Target.test(name: "Framework", product: .framework, settings: settings)
        let project = Project.test(path: "/Project/Path", settings: settings, targets: [target])
        let projectPath = project.path
        let graph = Graph.test(path: projectPath, projects: [projectPath: project])
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
            .willReturn(defaultConfigurationName)
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock).swiftlangVersion().willReturn("5.10.0")

        // When
        _ = try await subject.contentHashes(
            for: graph,
            configuration: nil,
            defaultConfiguration: defaultConfigurationName,
            excludedTargets: [],
            destination: nil
        )

        // Then
        verify(graphContentHasher)
            .contentHashes(
                for: .matching { graph in
                    guard let scopedProject = graph.projects[projectPath],
                          let targetSettings = scopedProject.targets[target.name]?.settings
                    else {
                        return false
                    }
                    return Set(scopedProject.settings.configurations.keys) == [selectedConfiguration]
                        && Set(targetSettings.configurations.keys) == [selectedConfiguration]
                },
                include: .any,
                destination: .any,
                additionalStrings: .any
            )
            .called(1)
    }

    @Test(
        .withMockedSwiftVersionProvider
    ) func contentHashes_preservesAllSettingsWhenConfigurationIsImplicit() async throws {
        // Given
        let selectedConfiguration = BuildConfiguration.debug("Debug-SharedCache")
        let unrelatedConfiguration = BuildConfiguration.debug("Debug-AppVariant-B")
        let settings = Settings(
            configurations: [
                selectedConfiguration: Configuration(settings: ["SELECTED": "YES"]),
                unrelatedConfiguration: Configuration(settings: ["UNRELATED": "YES"]),
            ]
        )
        let target = Target.test(name: "Framework", product: .framework, settings: settings)
        let project = Project.test(path: "/Project/Path", settings: settings, targets: [target])
        let projectPath = project.path
        let graph = Graph.test(path: projectPath, projects: [projectPath: project])
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
            .willReturn(selectedConfiguration.name)
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock).swiftlangVersion().willReturn("5.10.0")

        // When
        _ = try await subject.contentHashes(
            for: graph,
            configuration: nil,
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )

        // Then
        verify(graphContentHasher)
            .contentHashes(
                for: .matching { graph in
                    guard let unscopedProject = graph.projects[projectPath],
                          let targetSettings = unscopedProject.targets[target.name]?.settings
                    else {
                        return false
                    }
                    return Set(unscopedProject.settings.configurations.keys) == [
                        selectedConfiguration,
                        unrelatedConfiguration,
                    ]
                        && Set(targetSettings.configurations.keys) == [
                            selectedConfiguration,
                            unrelatedConfiguration,
                        ]
                },
                include: .any,
                destination: .any,
                additionalStrings: .any
            )
            .called(1)
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

    @Test(
        .withMockedSwiftVersionProvider
    ) func contentHashes_when_target_is_test_bundle_hashes_are_not_computed() async throws {
        // Given
        let included = Target.test(name: "Included", product: .framework)
        let testSupport = Target.test(name: "TestSupport", product: .uiTests)
        let project = Project.test(
            path: "/Project/Path",
            targets: [included, testSupport]
        )
        let includedTarget = GraphTarget(
            path: project.path,
            target: project.targets["Included"]!,
            project: project
        )
        let xctestTarget = GraphTarget(
            path: project.path,
            target: project.targets["TestSupport"]!,
            project: project
        )
        let graph = Graph.test(
            path: project.path,
            projects: [
                project.path: project,
            ]
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
            for: graph,
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
                    filter(includedTarget) && !filter(xctestTarget)
                },
                destination: .any,
                additionalStrings: .any
            )
            .called(1)
    }

    @Test(
        .withMockedSwiftVersionProvider
    ) func contentHashes_when_framework_depends_on_XCTest_hashes_are_computed() async throws {
        // Given
        let testSupport = Target.test(name: "TestSupport", product: .framework)
        let project = Project.test(
            path: "/Project/Path",
            targets: [testSupport]
        )
        let testSupportTarget = GraphTarget(
            path: project.path,
            target: project.targets["TestSupport"]!,
            project: project
        )
        let graph = Graph.test(
            path: project.path,
            projects: [
                project.path: project,
            ],
            dependencies: [
                .target(name: testSupport.name, path: project.path): [
                    .testSDK(name: "XCTest.framework"),
                ],
            ]
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
            for: graph,
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
                    filter(testSupportTarget)
                },
                destination: .any,
                additionalStrings: .any
            )
            .called(1)
    }

    @Test(
        .withMockedSwiftVersionProvider
    ) func contentHashes_when_framework_enables_testing_search_paths_hashes_are_computed() async throws {
        // Given
        let testSupport = Target.test(
            name: "TestSupport",
            product: .framework,
            settings: .test(base: [
                "ENABLE_TESTING_SEARCH_PATHS": "YES",
            ])
        )
        let project = Project.test(
            path: "/Project/Path",
            targets: [testSupport]
        )
        let testSupportTarget = GraphTarget(
            path: project.path,
            target: project.targets["TestSupport"]!,
            project: project
        )
        let graph = Graph.test(
            path: project.path,
            projects: [
                project.path: project,
            ]
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
            for: graph,
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
                    filter(testSupportTarget)
                },
                destination: .any,
                additionalStrings: .any
            )
            .called(1)
    }

    @Test(
        .withMockedSwiftVersionProvider
    ) func contentHashes_when_targets_are_libraries_hashes_are_computed() async throws {
        // Given
        let staticLibrary = Target.test(name: "StaticLibrary", product: .staticLibrary)
        let dynamicLibrary = Target.test(name: "DynamicLibrary", product: .dynamicLibrary)
        let project = Project.test(
            path: "/Project/Path",
            targets: [staticLibrary, dynamicLibrary]
        )
        let staticLibraryTarget = GraphTarget(
            path: project.path,
            target: project.targets["StaticLibrary"]!,
            project: project
        )
        let dynamicLibraryTarget = GraphTarget(
            path: project.path,
            target: project.targets["DynamicLibrary"]!,
            project: project
        )
        let graph = Graph.test(
            path: project.path,
            projects: [
                project.path: project,
            ]
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
            for: graph,
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
                    filter(staticLibraryTarget) && filter(dynamicLibraryTarget)
                },
                destination: .any,
                additionalStrings: .any
            )
            .called(1)
    }
}
