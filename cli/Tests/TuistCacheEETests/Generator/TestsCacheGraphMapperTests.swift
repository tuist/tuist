import Foundation
import Mockable
import Path
import TuistAutomation
import TuistCache
import TuistCore
import TuistHasher
import TuistServer
import XcodeGraph
import XCTest

@testable import TuistCacheEE
@testable import TuistTesting

final class TestsCacheMapperTests: TuistUnitTestCase {
    private var hashesCacheDirectory: AbsolutePath!
    private var testsCacheDirectory: AbsolutePath!
    private var graphContentHasher: MockGraphContentHashing!
    private var subject: TestsCacheGraphMapper!
    private var cacheStorage: MockCacheStoring!
    private var cacheDirectoriesProvider: CacheDirectoriesProvider!

    override func setUpWithError() throws {
        try super.setUpWithError()
        hashesCacheDirectory = try temporaryPath()
        graphContentHasher = .init()
        cacheStorage = MockCacheStoring()
        cacheDirectoriesProvider = CacheDirectoriesProvider()

        subject = TestsCacheGraphMapper(
            testPlan: nil,
            includedTargets: [],
            excludedTargets: [],
            graphContentHasher: graphContentHasher,
            cacheStorage: cacheStorage,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            ignoreSelectiveTesting: false,
            destination: nil
        )
    }

    override func tearDown() {
        hashesCacheDirectory = nil
        graphContentHasher = nil
        cacheDirectoriesProvider = nil
        cacheStorage = nil
        subject = nil
        super.tearDown()
    }

    // SchemeA: UnitTestsA -> FrameworkA (both cached)
    // SchemeB: UnitTestsA -> FrameworkA, UnitTestsB (UnitTestsB not cached)
    func test_map_when_only_one_unit_test_target_is_cached() async throws {
        let frameworkATarget = Target.test(
            name: "FrameworkA"
        )
        let unitTestsATarget = Target.test(
            name: "UnitTestsA",
            dependencies: [
                .target(name: "FrameworkA"),
            ]
        )
        let unitTestsBTarget = Target.test(
            name: "UnitTestsB"
        )
        let project = Project.test(targets: [frameworkATarget, unitTestsATarget, unitTestsBTarget])
        let frameworkA = GraphTarget.test(
            path: project.path,
            target: frameworkATarget,
            project: project
        )
        let unitTestsA = GraphTarget.test(
            path: project.path,
            target: unitTestsATarget,
            project: project
        )
        let unitTestsB = GraphTarget.test(
            path: project.path,
            target: unitTestsBTarget,
            project: project
        )

        let workspace = Workspace.test(
            schemes: [
                Scheme.test(
                    name: "SchemeA",
                    buildAction: .test(
                        targets: [
                            TargetReference(
                                projectPath: project.path,
                                name: unitTestsA.target.name
                            ),
                        ]
                    ),
                    testAction: TestAction.test(
                        targets: [
                            TestableTarget(
                                target: TargetReference(
                                    projectPath: project.path,
                                    name: unitTestsA.target.name
                                )
                            ),
                        ]
                    )
                ),
                Scheme.test(
                    name: "SchemeB",
                    buildAction: .test(
                        targets: [
                            TargetReference(
                                projectPath: project.path,
                                name: unitTestsA.target.name
                            ),
                            TargetReference(
                                projectPath: project.path,
                                name: unitTestsB.target.name
                            ),
                        ]
                    ),
                    testAction: TestAction.test(
                        targets: [
                            TestableTarget(
                                target: TargetReference(
                                    projectPath: project.path,
                                    name: unitTestsA.target.name
                                )
                            ),
                            TestableTarget(
                                target: TargetReference(
                                    projectPath: project.path,
                                    name: unitTestsB.target.name
                                )
                            ),
                        ]
                    )
                ),
            ]
        )

        let graph = Graph.test(
            workspace: workspace,
            projects: [project.path: project],
            dependencies: [
                .target(name: unitTestsA.target.name, path: unitTestsA.path): [
                    .target(name: frameworkA.target.name, path: frameworkA.path),
                ],
                .target(name: unitTestsB.target.name, path: unitTestsB.path): [
                    .target(name: frameworkA.target.name, path: frameworkA.path),
                ],
            ]
        )

        given(graphContentHasher)
            .contentHashes(
                for: .value(graph),
                include: .any,
                destination: .any,
                additionalStrings: .any
            )
            .willReturn(
                GraphTraverser(graph: graph).allTargets().reduce(into: [:]) { acc, target in
                    acc[target] = .test(hash: target.target.name)
                }
            )

        let cachePath = try temporaryPath()
        let unitTestsAStorableItem = CacheStorableItem(name: "UnitTestsA", hash: "UnitTestsA")
        let unitTestsBStorableItem = CacheStorableItem(name: "UnitTestsB", hash: "UnitTestsB")
        let frameworkAStorableItem = CacheStorableItem(name: "FrameworkA", hash: "FrameworkA")
        let unitTestsACacheItem: CacheItem = .test(name: "UnitTestsA", hash: "UnitTestsA")
        let frameworkACacheItem: CacheItem = .test(name: "FrameworkA", hash: "FrameworkA")
        given(cacheStorage).fetch(
            .value(Set([unitTestsAStorableItem, frameworkAStorableItem, unitTestsBStorableItem])),
            cacheCategory: .value(.selectiveTests)
        ).willReturn([
            unitTestsACacheItem: cachePath.appending(component: "unitTestsAItem"),
            frameworkACacheItem: cachePath.appending(component: "frameworkAItem"),
        ])

        // When
        let (gotGraph, _, gotMapperEnvironment) = try await subject.map(
            graph: graph,
            environment: MapperEnvironment()
        )

        // Then

        // The graphs are equal here because `prune` is not taken into account when testing equality of `XcodeGraph.Target`
        XCTAssertEqual(
            gotGraph,
            graph
        )
        XCTAssertEqual(
            gotMapperEnvironment.targetTestHashes,
            [
                project.path: [
                    "UnitTestsA": "UnitTestsA",
                    "UnitTestsB": "UnitTestsB",
                    "FrameworkA": "FrameworkA",
                ],
            ]
        )
        XCTAssertEqual(
            gotMapperEnvironment.targetTestCacheItems,
            [
                project.path: [
                    "UnitTestsA": unitTestsACacheItem,
                    "FrameworkA": frameworkACacheItem,
                ],
            ]
        )
        let targetsToPrune = gotGraph.projects.values
            .flatMap(\.targets.values)
            .filter { $0.metadata.tags.contains("tuist:prunable") }
            .sorted(by: { $0.name < $1.name })
        XCTAssertEqual(
            targetsToPrune,
            [
                unitTestsATarget,
            ]
        )
    }

    // SchemeA: UITestsA -> FrameworkA (both cached)
    // SchemeB: UITestsA -> FrameworkA, UITestsB (UITestsB not cached)
    func test_map_when_only_one_ui_test_target_is_cached() async throws {
        let frameworkATarget = Target.test(
            name: "FrameworkA"
        )
        let uiTestsATarget = Target.test(
            name: "UITestsA",
            product: .uiTests,
            dependencies: [
                .target(name: "FrameworkA"),
            ]
        )
        let uiTestsBTarget = Target.test(
            name: "UITestsB",
            product: .uiTests
        )
        let project = Project.test(targets: [frameworkATarget, uiTestsATarget, uiTestsBTarget])
        let frameworkA = GraphTarget.test(
            path: project.path,
            target: frameworkATarget,
            project: project
        )
        let uiTestsA = GraphTarget.test(
            path: project.path,
            target: uiTestsATarget,
            project: project
        )
        let uiTestsB = GraphTarget.test(
            path: project.path,
            target: uiTestsBTarget,
            project: project
        )

        let workspace = Workspace.test(
            schemes: [
                Scheme.test(
                    name: "SchemeA",
                    buildAction: .test(
                        targets: [
                            TargetReference(
                                projectPath: project.path,
                                name: uiTestsA.target.name
                            ),
                        ]
                    ),
                    testAction: TestAction.test(
                        targets: [
                            TestableTarget(
                                target: TargetReference(
                                    projectPath: project.path,
                                    name: uiTestsA.target.name
                                )
                            ),
                        ]
                    )
                ),
                Scheme.test(
                    name: "SchemeB",
                    buildAction: .test(
                        targets: [
                            TargetReference(
                                projectPath: project.path,
                                name: uiTestsA.target.name
                            ),
                            TargetReference(
                                projectPath: project.path,
                                name: uiTestsB.target.name
                            ),
                        ]
                    ),
                    testAction: TestAction.test(
                        targets: [
                            TestableTarget(
                                target: TargetReference(
                                    projectPath: project.path,
                                    name: uiTestsA.target.name
                                )
                            ),
                            TestableTarget(
                                target: TargetReference(
                                    projectPath: project.path,
                                    name: uiTestsB.target.name
                                )
                            ),
                        ]
                    )
                ),
            ]
        )

        let graph = Graph.test(
            workspace: workspace,
            projects: [project.path: project],
            dependencies: [
                .target(name: uiTestsA.target.name, path: uiTestsA.path): [
                    .target(name: frameworkA.target.name, path: frameworkA.path),
                ],
                .target(name: uiTestsB.target.name, path: uiTestsB.path): [
                    .target(name: frameworkA.target.name, path: frameworkA.path),
                ],
            ]
        )

        given(graphContentHasher)
            .contentHashes(
                for: .value(graph),
                include: .any,
                destination: .any,
                additionalStrings: .any
            )
            .willReturn(
                GraphTraverser(graph: graph).allTargets().reduce(into: [:]) { acc, target in
                    acc[target] = .test(hash: target.target.name)
                }
            )

        let cachePath = try temporaryPath()
        let uiTestsAStorableItem = CacheStorableItem(name: "UITestsA", hash: "UITestsA")
        let uiTestsBStorableItem = CacheStorableItem(name: "UITestsB", hash: "UITestsB")
        let frameworkAStorableItem = CacheStorableItem(name: "FrameworkA", hash: "FrameworkA")
        let uiTestsACacheItem: CacheItem = .test(name: "UITestsA", hash: "UITestsA")
        let frameworkACacheItem: CacheItem = .test(name: "FrameworkA", hash: "FrameworkA")
        given(cacheStorage).fetch(
            .value(Set([uiTestsAStorableItem, frameworkAStorableItem, uiTestsBStorableItem])),
            cacheCategory: .value(.selectiveTests)
        ).willReturn([
            uiTestsACacheItem: cachePath.appending(component: "unitTestsAItem"),
            frameworkACacheItem: cachePath.appending(component: "frameworkAItem"),
        ])

        // When
        let (gotGraph, _, gotMapperEnvironment) = try await subject.map(
            graph: graph,
            environment: MapperEnvironment()
        )

        // Then

        // The graphs are equal here because `prune` is not taken into account when testing equality of `XcodeGraph.Target`
        XCTAssertEqual(
            gotGraph,
            graph
        )
        XCTAssertEqual(
            gotMapperEnvironment.targetTestHashes,
            [
                project.path: [
                    "UITestsA": "UITestsA",
                    "UITestsB": "UITestsB",
                    "FrameworkA": "FrameworkA",
                ],
            ]
        )
        XCTAssertEqual(
            gotMapperEnvironment.targetTestCacheItems,
            [
                project.path: [
                    "UITestsA": uiTestsACacheItem,
                    "FrameworkA": frameworkACacheItem,
                ],
            ]
        )
        let targetsToPrune = gotGraph.projects.values
            .flatMap(\.targets.values)
            .filter { $0.metadata.tags.contains("tuist:prunable") }
            .sorted(by: { $0.name < $1.name })
        XCTAssertEqual(
            targetsToPrune,
            [
                uiTestsATarget,
            ]
        )
    }

    // SchemeA: UnitTestsA -> FrameworkA (only UnitTestsA cached)
    func test_map_only_tests_cached() async throws {
        let frameworkATarget = Target.test(
            name: "FrameworkA"
        )
        let unitTestsATarget = Target.test(
            name: "UnitTestsA",
            dependencies: [
                .target(name: "FrameworkA"),
            ]
        )
        let project = Project.test(targets: [frameworkATarget, unitTestsATarget])
        let frameworkA = GraphTarget.test(
            path: project.path,
            target: frameworkATarget,
            project: project
        )
        let unitTestsA = GraphTarget.test(
            path: project.path,
            target: unitTestsATarget,
            project: project
        )

        let schemeA = Scheme.test(
            name: "SchemeA",
            buildAction: .test(
                targets: [
                    TargetReference(
                        projectPath: project.path,
                        name: unitTestsA.target.name
                    ),
                ]
            ),
            testAction: TestAction.test(
                targets: [
                    TestableTarget(
                        target: TargetReference(
                            projectPath: project.path,
                            name: unitTestsA.target.name
                        )
                    ),
                ]
            )
        )

        let workspace = Workspace.test(
            schemes: [
                schemeA,
            ]
        )

        let graph = Graph.test(
            workspace: workspace,
            projects: [project.path: project],
            dependencies: [
                .target(name: unitTestsA.target.name, path: unitTestsA.path): [
                    .target(name: frameworkA.target.name, path: frameworkA.path),
                ],
            ]
        )

        given(graphContentHasher)
            .contentHashes(
                for: .value(graph),
                include: .any,
                destination: .any,
                additionalStrings: .any
            )
            .willReturn(
                GraphTraverser(graph: graph).allTargets().reduce(into: [:]) { acc, target in
                    acc[target] = .test(hash: target.target.name)
                }
            )

        let unitTestsAStorableItem = CacheStorableItem(name: "UnitTestsA", hash: "UnitTestsA")
        let frameworkAStorableItem = CacheStorableItem(name: "FrameworkA", hash: "FrameworkA")
        let unitTestsACacheItem: CacheItem = .test(name: "UnitTestsA", hash: "UnitTestsA")

        let cachePath = try temporaryPath()
        given(cacheStorage).fetch(
            .value(Set([unitTestsAStorableItem, frameworkAStorableItem])),
            cacheCategory: .value(.selectiveTests)
        )
        .willReturn([
            unitTestsACacheItem: cachePath.appending(component: "unitTestsA"),
        ])

        // When
        let (gotGraph, _, gotMapperEnvironment) = try await subject.map(
            graph: graph,
            environment: MapperEnvironment()
        )

        // Then
        XCTAssertEqual(
            gotGraph,
            graph
        )
        XCTAssertEqual(
            gotMapperEnvironment.targetTestHashes,
            [
                project.path: [
                    "UnitTestsA": "UnitTestsA",
                    "FrameworkA": "FrameworkA",
                ],
            ]
        )
        XCTAssertEqual(
            gotMapperEnvironment.targetTestCacheItems,
            [
                project.path: [
                    "UnitTestsA": unitTestsACacheItem,
                ],
            ]
        )
    }

    func test_map_preserves_prune() async throws {
        // Given
        let projectPath = try temporaryPath()
        let graph = Graph.test(
            projects: [
                projectPath: .test(
                    targets: [
                        .test(
                            name: "UITests",
                            product: .uiTests,
                            metadata: TargetMetadata.metadata(tags: Set(["tuist:prunable"]))
                        ),
                        .test(name: "UnitTests", product: .unitTests, prune: false),
                    ]
                ),
            ]
        )

        given(graphContentHasher)
            .contentHashes(
                for: .value(graph),
                include: .any,
                destination: .any,
                additionalStrings: .any
            )
            .willReturn(
                GraphTraverser(graph: graph).allTargets().reduce(into: [:]) { acc, target in
                    acc[target] = .test(hash: target.target.name)
                }
            )

        given(cacheStorage).fetch(
            .any,
            cacheCategory: .value(.selectiveTests)
        ).willReturn([:])

        // When
        let (gotGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEqual(
            gotGraph,
            graph
        )
        XCTAssertEqual(
            gotGraph
                .projects
                .flatMap(\.value.targets.values)
                .filter { $0.metadata.tags.contains("tuist:prunable") },
            [
                .test(name: "UITests", product: .uiTests, prune: true),
            ]
        )
    }

    func test_when_ignore_selective_testing() async throws {
        // Given
        subject = TestsCacheGraphMapper(
            testPlan: nil,
            includedTargets: [],
            excludedTargets: [],
            graphContentHasher: graphContentHasher,
            cacheStorage: cacheStorage,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            ignoreSelectiveTesting: true,
            destination: nil
        )
        let frameworkATarget = Target.test(
            name: "FrameworkA"
        )
        let unitTestsATarget = Target.test(
            name: "UnitTestsA",
            dependencies: [
                .target(name: "FrameworkA"),
            ]
        )
        let project = Project.test(targets: [frameworkATarget, unitTestsATarget])
        let frameworkA = GraphTarget.test(
            path: project.path,
            target: frameworkATarget,
            project: project
        )
        let unitTestsA = GraphTarget.test(
            path: project.path,
            target: unitTestsATarget,
            project: project
        )

        let workspace = Workspace.test(
            schemes: [
                Scheme.test(
                    name: "SchemeA",
                    buildAction: .test(
                        targets: [
                            TargetReference(
                                projectPath: project.path,
                                name: unitTestsA.target.name
                            ),
                        ]
                    ),
                    testAction: TestAction.test(
                        targets: [
                            TestableTarget(
                                target: TargetReference(
                                    projectPath: project.path,
                                    name: unitTestsA.target.name
                                )
                            ),
                        ]
                    )
                ),
            ]
        )

        let graph = Graph.test(
            workspace: workspace,
            projects: [project.path: project],
            dependencies: [
                .target(name: unitTestsA.target.name, path: unitTestsA.path): [
                    .target(name: frameworkA.target.name, path: frameworkA.path),
                ],
            ]
        )

        given(graphContentHasher)
            .contentHashes(
                for: .value(graph),
                include: .any,
                destination: .any,
                additionalStrings: .any
            )
            .willReturn(
                GraphTraverser(graph: graph).allTargets().reduce(into: [:]) { acc, target in
                    acc[target] = .test(hash: target.target.name)
                }
            )

        let cachePath = try temporaryPath()
        let unitTestsAStorableItem = CacheStorableItem(name: "UnitTestsA", hash: "UnitTestsA")
        let frameworkAStorableItem = CacheStorableItem(name: "FrameworkA", hash: "FrameworkA")
        let unitTestsACacheItem: CacheItem = .test(name: "UnitTestsA", hash: "UnitTestsA")
        let frameworkACacheItem: CacheItem = .test(name: "FrameworkA", hash: "FrameworkA")
        given(cacheStorage).fetch(
            .value(Set([unitTestsAStorableItem, frameworkAStorableItem])),
            cacheCategory: .value(.selectiveTests)
        ).willReturn([
            unitTestsACacheItem: cachePath.appending(component: "unitTestsAItem"),
            frameworkACacheItem: cachePath.appending(component: "frameworkAItem"),
        ])

        // When
        let (gotGraph, _, gotMapperEnvironment) = try await subject.map(
            graph: graph,
            environment: MapperEnvironment()
        )

        // Then

        // The graphs are equal here because `prune` is not taken into account when testing equality of `XcodeGraph.Target`
        XCTAssertEqual(
            gotGraph,
            graph
        )
        XCTAssertEqual(
            gotMapperEnvironment.targetTestHashes,
            [
                project.path: [
                    "UnitTestsA": "UnitTestsA",
                    "FrameworkA": "FrameworkA",
                ],
            ]
        )
        XCTAssertEqual(
            gotMapperEnvironment.targetTestCacheItems,
            [:]
        )
        let targetsToPrune = gotGraph.projects.values
            .flatMap(\.targets.values)
            .filter { $0.metadata.tags.contains("tuist:prunable") }
            .sorted(by: { $0.name < $1.name })
        XCTAssertEmpty(targetsToPrune)
    }
}
