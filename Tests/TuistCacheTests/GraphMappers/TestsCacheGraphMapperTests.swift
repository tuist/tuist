import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import XCTest

@testable import TuistCache
@testable import TuistCacheTesting
@testable import TuistCoreTesting
@testable import TuistGraphTesting
@testable import TuistSupportTesting

final class TestsCacheMapperTests: TuistUnitTestCase {
    private var hashesCacheDirectory: AbsolutePath!
    private var testsCacheDirectory: AbsolutePath!
    private var graphContentHasher: MockGraphContentHasher!
    private var subject: TestsCacheGraphMapper!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProvider!

    override func setUpWithError() throws {
        try super.setUpWithError()
        hashesCacheDirectory = try temporaryPath()
        graphContentHasher = MockGraphContentHasher()
        testsCacheDirectory = try temporaryPath()
        cacheDirectoriesProvider = try MockCacheDirectoriesProvider()
        cacheDirectoriesProvider.cacheDirectoryStub = testsCacheDirectory
        subject = TestsCacheGraphMapper(
            hashesCacheDirectory: hashesCacheDirectory,
            config: Config.default,
            graphContentHasher: graphContentHasher,
            cacheDirectoryProviderFactory: MockCacheDirectoriesProviderFactory(provider: cacheDirectoriesProvider)
        )
    }

    override func tearDown() {
        hashesCacheDirectory = nil
        graphContentHasher = nil
        subject = nil
        super.tearDown()
    }

    // SchemeA: UnitTestsA -> FrameworkA (both cached)
    // SchemeB: UnitTestsA -> FrameworkA, UnitTestsB (UnitTestsB cached)
    func test_map_all_cached() throws {
        let project = Project.test()
        let frameworkA = GraphTarget.test(
            path: project.path,
            target: Target.test(
                name: "FrameworkA"
            ),
            project: project
        )
        let unitTestsA = GraphTarget.test(
            path: project.path,
            target: Target.test(
                name: "UnitTestsA",
                dependencies: [
                    .target(name: "FrameworkA"),
                ]
            ),
            project: project
        )
        let unitTestsB = GraphTarget.test(
            path: project.path,
            target: Target.test(
                name: "UnitTestsB"
            ),
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
            targets: [
                project.path: [
                    frameworkA.target.name: frameworkA.target,
                    unitTestsA.target.name: unitTestsA.target,
                    unitTestsB.target.name: unitTestsB.target,
                ],
            ],
            dependencies: [
                .target(name: unitTestsA.target.name, path: unitTestsA.path): [
                    .target(name: frameworkA.target.name, path: frameworkA.path),
                ],
                .target(name: unitTestsB.target.name, path: unitTestsB.path): [
                    .target(name: frameworkA.target.name, path: frameworkA.path),
                ],
            ]
        )

        graphContentHasher.contentHashesStub = { graph, _, _ in
            GraphTraverser(graph: graph).allTargets().reduce(into: [:]) { acc, target in
                acc[target] = target.target.name
            }
        }

        try fileHandler.touch(
            cacheDirectoriesProvider.cacheDirectory(for: .tests).appending(component: "FrameworkA")
        )
        try fileHandler.touch(
            cacheDirectoriesProvider.cacheDirectory(for: .tests).appending(component: "UnitTestsA")
        )

        let expectedGraph = Graph.test(
            workspace: Workspace.test(
                schemes: [
                    Scheme.test(
                        name: "SchemeA",
                        buildAction: BuildAction.test(
                            targets: []
                        ),
                        testAction: TestAction.test(
                            targets: []
                        )
                    ),
                    Scheme.test(
                        name: "SchemeB",
                        buildAction: BuildAction.test(
                            targets: [
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
                                        name: unitTestsB.target.name
                                    )
                                ),
                            ]
                        )
                    ),
                ]
            ),
            projects: [project.path: project],
            targets: [
                project.path: [
                    frameworkA.target.name: frameworkA.target,
                    unitTestsA.target.name: unitTestsA.target,
                    unitTestsB.target.name: unitTestsB.target,
                ],
            ],
            dependencies: [
                .target(name: unitTestsA.target.name, path: unitTestsA.path): [
                    .target(name: frameworkA.target.name, path: frameworkA.path),
                ],
                .target(name: unitTestsB.target.name, path: unitTestsB.path): [
                    .target(name: frameworkA.target.name, path: frameworkA.path),
                ],
            ]
        )

        // When
        let (gotGraph, gotSideEffects) = try subject.map(graph: graph)

        // Then
        XCTAssertEqual(
            gotGraph,
            expectedGraph
        )
        XCTAssertEqual(
            gotSideEffects.sorted(by: {
                switch ($0, $1) {
                case let (.file(fileDescriptorA), .file(fileDescriptorB)):
                    return fileDescriptorA.path < fileDescriptorB.path
                default:
                    return false
                }
            }),
            [
                .file(
                    FileDescriptor(path: hashesCacheDirectory.appending(component: "FrameworkA"))
                ),
                .file(
                    FileDescriptor(path: hashesCacheDirectory.appending(component: "UnitTestsA"))
                ),
                .file(
                    FileDescriptor(path: hashesCacheDirectory.appending(component: "UnitTestsB"))
                ),
            ]
        )

        let output = TestingLogHandler.collected[.notice, ==]
        XCTAssertEqual(
            output.components(separatedBy: "UnitTestsA has not changed from last successful run, skipping...").count - 1,
            1
        )
    }

    // SchemeA: UnitTestsA -> FrameworkA (only UnitTestsA cached)
    func test_map_only_tests_cached() throws {
        let project = Project.test()
        let frameworkA = GraphTarget.test(
            path: project.path,
            target: Target.test(
                name: "FrameworkA"
            ),
            project: project
        )
        let unitTestsA = GraphTarget.test(
            path: project.path,
            target: Target.test(
                name: "UnitTestsA",
                dependencies: [
                    .target(name: "FrameworkA"),
                ]
            ),
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
            targets: [
                project.path: [
                    frameworkA.target.name: frameworkA.target,
                    unitTestsA.target.name: unitTestsA.target,
                ],
            ],
            dependencies: [
                .target(name: unitTestsA.target.name, path: unitTestsA.path): [
                    .target(name: frameworkA.target.name, path: frameworkA.path),
                ],
            ]
        )

        graphContentHasher.contentHashesStub = { graph, _, _ in
            GraphTraverser(graph: graph).allTargets().reduce(into: [:]) { acc, target in
                acc[target] = target.target.name
            }
        }

        try fileHandler.touch(
            hashesCacheDirectory.appending(component: "UnitTestsA")
        )

        let expectedGraph = Graph.test(
            workspace: Workspace.test(
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
            ),
            projects: [project.path: project],
            targets: [
                project.path: [
                    frameworkA.target.name: frameworkA.target,
                    unitTestsA.target.name: unitTestsA.target,
                ],
            ],
            dependencies: [
                .target(name: unitTestsA.target.name, path: unitTestsA.path): [
                    .target(name: frameworkA.target.name, path: frameworkA.path),
                ],
            ]
        )

        // When
        let (gotGraph, gotSideEffects) = try subject.map(graph: graph)

        // Then
        XCTAssertEqual(
            gotGraph,
            expectedGraph
        )
        XCTAssertEqual(
            gotSideEffects.sorted(by: {
                switch ($0, $1) {
                case let (.file(fileDescriptorA), .file(fileDescriptorB)):
                    return fileDescriptorA.path < fileDescriptorB.path
                default:
                    return false
                }
            }),
            [
                .file(
                    FileDescriptor(path: hashesCacheDirectory.appending(component: "FrameworkA"))
                ),
                .file(
                    FileDescriptor(path: hashesCacheDirectory.appending(component: "UnitTestsA"))
                ),
            ]
        )
    }
}
