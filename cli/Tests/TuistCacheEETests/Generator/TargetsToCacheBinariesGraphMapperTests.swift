import Foundation
import Mockable
import TuistCache
import TuistCore
import TuistHasher
import TuistServer
import XcodeGraph
import XCTest

@testable import TuistCacheEE
@testable import TuistTesting

final class TargetsToCacheBinariesGraphMapperTests: TuistUnitTestCase {
    private var cacheStorage: MockCacheStoring!
    private var cacheGraphContentHasher: MockCacheGraphContentHashing!
    private var cacheGraphMutator: MockCacheGraphMutating!
    private var subject: TargetsToCacheBinariesGraphMapper!
    private var config: Tuist!

    override func setUp() {
        super.setUp()
        config = .test()
        cacheStorage = MockCacheStoring()
        cacheGraphContentHasher = MockCacheGraphContentHashing()
        cacheGraphMutator = .init()
        subject = TargetsToCacheBinariesGraphMapper(
            config: config,
            cacheGraphContentHasher: cacheGraphContentHasher,
            decider: CacheProfileTargetReplacementDecider(profile: .allPossible, exceptions: []),
            configuration: "Debug",
            cacheGraphMutator: cacheGraphMutator,
            cacheStorage: cacheStorage
        )
    }

    override func tearDown() {
        config = nil
        cacheStorage = nil
        cacheGraphContentHasher = nil
        cacheGraphMutator = nil
        subject = nil
        super.tearDown()
    }

    func test_map_when_sources_are_tests() async throws {
        let path = try temporaryPath()
        let project = Project.test(path: path)

        // Given
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cGraphTarget = GraphTarget.test(path: path, target: cFramework)
        let cHash = "C"

        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bGraphTarget = GraphTarget.test(path: path, target: bFramework)
        let bHash = "B"
        let bXCFrameworkPath = path.appending(component: "B.xcframework")

        let bUnitTests = Target.test(name: "BTests", platform: .iOS, product: .unitTests)
        let bUnitTestsGraphTarget = GraphTarget.test(path: path, target: bUnitTests)

        let cUnitTests = Target.test(name: "CTests", platform: .iOS, product: .unitTests)
        let cUnitTestsGraphTarget = GraphTarget.test(path: path, target: cUnitTests)

        let inputGraph = Graph.test(
            name: "input",
            projects: [path: project],
            dependencies: [
                .target(name: bUnitTests.name, path: bUnitTestsGraphTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                ],
                .target(name: cUnitTests.name, path: cUnitTestsGraphTarget.path): [
                    .target(name: cFramework.name, path: cGraphTarget.path),
                ],
            ]
        )
        let outputGraph = Graph.test(
            name: "output",
            projects: inputGraph.projects,
            dependencies: inputGraph.dependencies
        )

        let contentHashes: [GraphTarget: TargetContentHash] = [
            cGraphTarget: .test(hash: cHash),
            bGraphTarget: .test(hash: bHash),
        ]
        given(cacheGraphContentHasher)
            .contentHashes(
                for: .any,
                configuration: .any,
                defaultConfiguration: .any,
                excludedTargets: .any,
                destination: .any
            )
            .willReturn(contentHashes)

        let cachePath = try temporaryPath()
        given(cacheStorage).fetch(
            .value(
                Set([
                    CacheStorableItem(name: "B", hash: bHash),
                    CacheStorableItem(name: "C", hash: cHash),
                ])
            ), cacheCategory: .value(.binaries)
        ).willReturn([
            .test(name: "B", hash: bHash): cachePath.appending(component: "B"),
            .test(name: "C", hash: cHash): cachePath.appending(component: "C"),
        ])

        given(cacheStorage).fetch(
            .value(
                Set([
                    CacheStorableItem(name: "B", hash: bHash),
                    CacheStorableItem(name: "C", hash: cHash),
                ])
            ), cacheCategory: .value(.binaries)
        ).willReturn([
            .test(name: "B", hash: bHash): bXCFrameworkPath,
        ])

        given(cacheGraphMutator)
            .map(
                graph: .any,
                precompiledArtifacts: .any,
                sources: .any,
                keepSourceTargets: .value(
                    config.project.generatedProject?.cacheOptions.keepSourceTargets ?? false
                )
            )
            .willReturn(outputGraph)

        // When
        let (got, _, gotEnvironment) = try await subject.map(
            graph: inputGraph, environment: MapperEnvironment()
        )

        // Then
        XCTAssertEqual(
            got,
            outputGraph
        )
        XCTAssertEqual(
            gotEnvironment.initialGraphWithSources,
            inputGraph
        )
    }

    func test_map_when_all_binaries_are_fetched_successfully() async throws {
        let path = try temporaryPath()
        let project = Project.test(path: path)

        // Given
        subject = TargetsToCacheBinariesGraphMapper(
            config: config,
            cacheGraphContentHasher: cacheGraphContentHasher,
            decider: CacheProfileTargetReplacementDecider(profile: .allPossible, exceptions: []),
            configuration: "Debug",
            cacheGraphMutator: cacheGraphMutator,
            cacheStorage: cacheStorage
        )
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cGraphTarget = GraphTarget.test(path: path, target: cFramework)
        let cXCFrameworkPath = path.appending(component: "C.xcframework")
        let cHash = "C"

        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bGraphTarget = GraphTarget.test(path: path, target: bFramework)
        let bHash = "B"
        let bXCFrameworkPath = path.appending(component: "B.xcframework")

        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let appGraphTarget = GraphTarget.test(path: path, target: app)
        let appHash = "App"

        let inputGraph = Graph.test(
            name: "input",
            projects: [path: project],
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    .target(name: cFramework.name, path: cGraphTarget.path),
                ],
                .target(name: app.name, path: appGraphTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                ],
            ]
        )
        let outputGraph = Graph.test(
            name: "output",
            projects: inputGraph.projects,
            dependencies: inputGraph.dependencies
        )

        let contentHashes: [GraphTarget: TargetContentHash] = [
            cGraphTarget: .test(hash: cHash),
            bGraphTarget: .test(hash: bHash),
            appGraphTarget: .test(hash: appHash),
        ]
        given(cacheGraphContentHasher)
            .contentHashes(
                for: .any,
                configuration: .any,
                defaultConfiguration: .any,
                excludedTargets: .any,
                destination: .any
            )
            .willReturn(contentHashes)
        let cachePath = try temporaryPath()
        given(cacheStorage).fetch(
            .value(
                Set([
                    CacheStorableItem(name: "B", hash: bHash),
                    CacheStorableItem(name: "C", hash: cHash),
                ])
            ), cacheCategory: .value(.binaries)
        ).willReturn([
            .test(name: "B", hash: bHash): cachePath.appending(component: "B"),
            .test(name: "C", hash: cHash): cachePath.appending(component: "C"),
        ])
        given(cacheStorage).fetch(
            .value(
                Set([
                    CacheStorableItem(name: "B", hash: bHash),
                ])
            ), cacheCategory: .value(.binaries)
        ).willReturn([
            .test(name: "B", hash: bHash): bXCFrameworkPath,
            .test(name: "C", hash: bHash): cXCFrameworkPath,
        ])
        given(cacheGraphMutator)
            .map(
                graph: .any,
                precompiledArtifacts: .any,
                sources: .any,
                keepSourceTargets: .value(
                    config.project.generatedProject?.cacheOptions.keepSourceTargets ?? false
                )
            )
            .willReturn(outputGraph)
        given(cacheStorage).fetch(.any, cacheCategory: .value(.binaries)).willReturn([:])

        // When
        let (got, _, _) = try await subject.map(graph: inputGraph, environment: MapperEnvironment())

        // Then
        XCTAssertEqual(
            got,
            outputGraph
        )
    }

    /// Targets from the same package have the same hash as instead of hashing the targets individually, we use the package
    /// reference hash.
    func test_map_when_all_package_binaries_are_fetched_successfully() async throws {
        let path = try temporaryPath()
        let project = Project.test(path: path)

        // Given
        subject = TargetsToCacheBinariesGraphMapper(
            config: config,
            cacheGraphContentHasher: cacheGraphContentHasher,
            decider: CacheProfileTargetReplacementDecider(profile: .allPossible, exceptions: []),
            configuration: "Debug",
            cacheGraphMutator: cacheGraphMutator,
            cacheStorage: cacheStorage
        )
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cGraphTarget = GraphTarget.test(path: path, target: cFramework)
        let cXCFrameworkPath = path.appending(component: "C.xcframework")
        let packageHash = "package-hash"

        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bGraphTarget = GraphTarget.test(path: path, target: bFramework)
        let bXCFrameworkPath = path.appending(component: "B.xcframework")

        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let appGraphTarget = GraphTarget.test(path: path, target: app)
        let appHash = "App"

        let inputGraph = Graph.test(
            name: "input",
            projects: [path: project],
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    .target(name: cFramework.name, path: cGraphTarget.path),
                ],
                .target(name: app.name, path: appGraphTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                ],
            ]
        )
        let outputGraph = Graph.test(
            name: "output",
            projects: inputGraph.projects,
            dependencies: inputGraph.dependencies
        )

        let contentHashes: [GraphTarget: TargetContentHash] = [
            cGraphTarget: .test(hash: packageHash),
            bGraphTarget: .test(hash: packageHash),
            appGraphTarget: .test(hash: appHash),
        ]
        given(cacheGraphContentHasher)
            .contentHashes(
                for: .any,
                configuration: .any,
                defaultConfiguration: .any,
                excludedTargets: .any,
                destination: .any
            )
            .willReturn(contentHashes)
        let cachePath = try temporaryPath()
        given(cacheStorage).fetch(
            .value(
                Set([
                    CacheStorableItem(name: "B", hash: packageHash),
                    CacheStorableItem(name: "C", hash: packageHash),
                ])
            ), cacheCategory: .value(.binaries)
        ).willReturn([
            .test(name: "B", hash: packageHash): cachePath.appending(component: "B"),
            .test(name: "C", hash: packageHash): cachePath.appending(component: "C"),
        ])
        given(cacheStorage).fetch(
            .value(
                Set([
                    CacheStorableItem(name: "B", hash: packageHash),
                ])
            ), cacheCategory: .value(.binaries)
        ).willReturn([
            .test(name: "B", hash: packageHash): bXCFrameworkPath,
            .test(name: "C", hash: packageHash): cXCFrameworkPath,
        ])
        given(cacheGraphMutator)
            .map(
                graph: .any,
                precompiledArtifacts: .any,
                sources: .any,
                keepSourceTargets: .value(
                    config.project.generatedProject?.cacheOptions.keepSourceTargets ?? false
                )
            )
            .willReturn(outputGraph)
        let bBinaryPath = try temporaryPath().appending(component: "B-Binary")
        let cBinaryPath = try temporaryPath().appending(component: "C-Binary")
        given(cacheStorage).fetch(
            .any,
            cacheCategory: .value(.binaries)
        ).willReturn(
            [
                .test(name: "B", hash: "package-hash"): bBinaryPath,
                .test(name: "C", hash: "package-hash"): cBinaryPath,
            ]
        )

        // When
        let (got, _, _) = try await subject.map(graph: inputGraph, environment: MapperEnvironment())

        // Then
        XCTAssertEqual(
            got,
            outputGraph
        )
    }

    func test_map_forwards_correct_artifactType_to_hasher() async throws {
        // Given
        let path = try temporaryPath()
        let project = Project.test(path: path)

        subject = TargetsToCacheBinariesGraphMapper(
            config: config,
            cacheGraphContentHasher: cacheGraphContentHasher,
            decider: CacheProfileTargetReplacementDecider(profile: .allPossible, exceptions: []),
            configuration: "Debug",
            cacheGraphMutator: cacheGraphMutator,
            cacheStorage: cacheStorage
        )

        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cGraphTarget = GraphTarget.test(path: path, target: cFramework)

        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bGraphTarget = GraphTarget.test(path: path, target: bFramework)

        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let appGraphTarget = GraphTarget.test(path: path, target: app)

        let inputGraph = Graph.test(
            name: "input",
            projects: [path: project],
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    .target(name: cFramework.name, path: cGraphTarget.path),
                ],
                .target(name: app.name, path: appGraphTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                ],
            ]
        )
        let outputGraph = Graph.test(
            name: "output",
            projects: inputGraph.projects,
            dependencies: inputGraph.dependencies
        )
        given(cacheGraphMutator)
            .map(
                graph: .any,
                precompiledArtifacts: .any,
                sources: .any,
                keepSourceTargets: .value(
                    config.project.generatedProject?.cacheOptions.keepSourceTargets ?? false
                )
            )
            .willReturn(outputGraph)

        given(cacheGraphContentHasher)
            .contentHashes(
                for: .any,
                configuration: .value("Debug"),
                defaultConfiguration: .any,
                excludedTargets: .any,
                destination: .any
            )
            .willReturn([:])
        given(cacheStorage).fetch(.any, cacheCategory: .value(.binaries)).willReturn([:])

        // When / Then
        _ = try await subject.map(graph: inputGraph, environment: MapperEnvironment())
    }

    func test_map_when_excluded_targets_are_passed() async throws {
        let path = try temporaryPath()

        // Given
        subject = TargetsToCacheBinariesGraphMapper(
            config: config,
            cacheGraphContentHasher: cacheGraphContentHasher,
            decider: CacheProfileTargetReplacementDecider(profile: .allPossible, exceptions: []),
            configuration: "Debug",
            cacheGraphMutator: cacheGraphMutator,
            cacheStorage: cacheStorage
        )

        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bGraphTarget = GraphTarget.test(path: path, target: bFramework)

        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cGraphTarget = GraphTarget.test(path: path, target: cFramework)

        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let project = Project.test(path: path, targets: [app])

        let inputGraph = Graph.test(
            name: "input",
            projects: [path: project],
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [],
                .target(name: cFramework.name, path: cGraphTarget.path): [],
            ]
        )
        let outputGraph = Graph.test(
            name: "output",
            projects: inputGraph.projects,
            dependencies: inputGraph.dependencies
        )
        given(cacheGraphMutator)
            .map(
                graph: .any,
                precompiledArtifacts: .any,
                sources: .any,
                keepSourceTargets: .value(
                    config.project.generatedProject?.cacheOptions.keepSourceTargets ?? false
                )
            )
            .willReturn(outputGraph)

        given(cacheGraphContentHasher)
            .contentHashes(
                for: .any,
                configuration: .any,
                defaultConfiguration: .any,
                excludedTargets: .value(["App"]),
                destination: .any
            )
            .willReturn([:])
        given(cacheStorage).fetch(.any, cacheCategory: .value(.binaries)).willReturn([:])

        // When / Then
        _ = try await subject.map(graph: inputGraph, environment: MapperEnvironment())
    }

    func test_map_stores_subhashes_in_run_metadata_storage() async throws {
        let path = try temporaryPath()
        let project = Project.test(path: path)
        let runMetadataStorage = RunMetadataStorage()

        try await RunMetadataStorage.$current.withValue(runMetadataStorage) {
            // Given
            let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
            let cGraphTarget = GraphTarget.test(path: path, target: cFramework, project: project)
            let cHash = "C-hash"
            let cSubhashes = TargetContentHashSubhashes.test(
                sources: "c-sources",
                dependencies: "c-deps"
            )

            let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
            let bGraphTarget = GraphTarget.test(path: path, target: bFramework, project: project)
            let bHash = "B-hash"
            let bSubhashes = TargetContentHashSubhashes.test(
                sources: "b-sources",
                resources: "b-resources"
            )

            let app = Target.test(name: "App", platform: .iOS, product: .app)
            let appGraphTarget = GraphTarget.test(path: path, target: app, project: project)

            let inputGraph = Graph.test(
                name: "input",
                projects: [path: project],
                dependencies: [
                    .target(name: bFramework.name, path: bGraphTarget.path): [
                        .target(name: cFramework.name, path: cGraphTarget.path),
                    ],
                    .target(name: app.name, path: appGraphTarget.path): [
                        .target(name: bFramework.name, path: bGraphTarget.path),
                    ],
                ]
            )
            let outputGraph = Graph.test(
                name: "output",
                projects: inputGraph.projects,
                dependencies: inputGraph.dependencies
            )

            let contentHashes: [GraphTarget: TargetContentHash] = [
                cGraphTarget: .test(hash: cHash, subhashes: cSubhashes),
                bGraphTarget: .test(hash: bHash, subhashes: bSubhashes),
            ]
            given(cacheGraphContentHasher)
                .contentHashes(
                    for: .any,
                    configuration: .any,
                    defaultConfiguration: .any,
                    excludedTargets: .any,
                    destination: .any
                )
                .willReturn(contentHashes)
            given(cacheStorage).fetch(.any, cacheCategory: .value(.binaries)).willReturn([:])
            given(cacheGraphMutator)
                .map(
                    graph: .any,
                    precompiledArtifacts: .any,
                    sources: .any,
                    keepSourceTargets: .value(
                        config.project.generatedProject?.cacheOptions.keepSourceTargets ?? false
                    )
                )
                .willReturn(outputGraph)

            // When
            _ = try await subject.map(graph: inputGraph, environment: MapperEnvironment())

            // Then
            let storedSubhashes = await runMetadataStorage.targetContentHashSubhashes
            XCTAssertEqual(storedSubhashes[cHash], cSubhashes)
            XCTAssertEqual(storedSubhashes[bHash], bSubhashes)
        }
    }
}
