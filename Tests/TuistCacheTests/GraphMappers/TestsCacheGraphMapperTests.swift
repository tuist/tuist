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
    private var testsCacheDirectory: AbsolutePath!
    private var graphContentHasher: MockGraphContentHasher!
    private var subject: TestsCacheGraphMapper!

    override func setUpWithError() throws {
        try super.setUpWithError()
        testsCacheDirectory = try temporaryPath()
        graphContentHasher = MockGraphContentHasher()
        subject = TestsCacheGraphMapper(
            testsCacheDirectory: testsCacheDirectory,
            graphContentHasher: graphContentHasher
        )
    }

    override func tearDown() {
        testsCacheDirectory = nil
        graphContentHasher = nil
        subject = nil
        super.tearDown()
    }

    // SchemeA: UnitTestsA -> FrameworkA (both cached)
    // SchemeB: UnitTestsA -> FrameworkA, UnitTestsB (UnitTestsB cached)
    func test_map_all_cached() throws {
        let project = Project.test()
        let frameworkA = TargetNode.test(
            project: project,
            target: Target.test(
                name: "FrameworkA"
            )
        )
        let unitTestsA = TargetNode.test(
            project: project,
            target: Target.test(
                name: "UnitTestsA",
                dependencies: [
                    .target(name: "FrameworkA"),
                ]
            ),
            dependencies: [
                frameworkA,
            ]
        )
        let unitTestsB = TargetNode.test(
            project: project,
            target: Target.test(
                name: "UnitTestsB"
            ),
            dependencies: [
                frameworkA,
            ]
        )

        let workspace = Workspace.test(
            schemes: [
                Scheme.test(
                    name: "SchemeA",
                    testAction: TestAction.test(
                        targets: [
                            TestableTarget(
                                target: TargetReference(
                                    projectPath: project.path,
                                    name: unitTestsA.name
                                )
                            ),
                        ]
                    )
                ),
                Scheme.test(
                    name: "SchemeB",
                    testAction: TestAction.test(
                        targets: [
                            TestableTarget(
                                target: TargetReference(
                                    projectPath: project.path,
                                    name: unitTestsA.name
                                )
                            ),
                            TestableTarget(
                                target: TargetReference(
                                    projectPath: project.path,
                                    name: unitTestsB.name
                                )
                            ),
                        ]
                    )
                ),
            ]
        )

        let graph = Graph.test(
            workspace: workspace,
            projects: [project],
            targets: [
                project.path: [
                    frameworkA,
                    unitTestsA,
                    unitTestsB,
                ],
            ]
        )

        graphContentHasher.contentHashesStub = { graph, _, _ in
            graph.targets.flatMap(\.value).reduce(into: [:]) { acc, target in
                acc[target] = target.target.name
            }
        }

        try fileHandler.touch(
            environment.testsCacheDirectory.appending(component: "FrameworkA")
        )
        try fileHandler.touch(
            environment.testsCacheDirectory.appending(component: "UnitTestsA")
        )

        let expectedGraph = Graph.test(
            workspace: Workspace.test(
                schemes: [
                    Scheme.test(
                        name: "SchemeA",
                        testAction: TestAction.test(
                            targets: []
                        )
                    ),
                    Scheme.test(
                        name: "SchemeB",
                        testAction: TestAction.test(
                            targets: [
                                TestableTarget(
                                    target: TargetReference(
                                        projectPath: project.path,
                                        name: unitTestsB.name
                                    )
                                ),
                            ]
                        )
                    ),
                ]
            ),
            projects: [project],
            targets: [
                project.path: [
                    frameworkA,
                    unitTestsA,
                    unitTestsB,
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
                    FileDescriptor(path: testsCacheDirectory.appending(component: "FrameworkA"))
                ),
                .file(
                    FileDescriptor(path: testsCacheDirectory.appending(component: "UnitTestsA"))
                ),
                .file(
                    FileDescriptor(path: testsCacheDirectory.appending(component: "UnitTestsB"))
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
        let frameworkA = TargetNode.test(
            project: project,
            target: Target.test(
                name: "FrameworkA"
            )
        )
        let unitTestsA = TargetNode.test(
            project: project,
            target: Target.test(
                name: "UnitTestsA",
                dependencies: [
                    .target(name: "FrameworkA"),
                ]
            ),
            dependencies: [
                frameworkA,
            ]
        )

        let schemeA = Scheme.test(
            name: "SchemeA",
            testAction: TestAction.test(
                targets: [
                    TestableTarget(
                        target: TargetReference(
                            projectPath: project.path,
                            name: unitTestsA.name
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
            projects: [project],
            targets: [
                project.path: [
                    frameworkA,
                    unitTestsA,
                ],
            ]
        )

        graphContentHasher.contentHashesStub = { graph, _, _ in
            graph.targets.flatMap(\.value).reduce(into: [:]) { acc, target in
                acc[target] = target.target.name
            }
        }

        try fileHandler.touch(
            environment.testsCacheDirectory.appending(component: "UnitTestsA")
        )

        let expectedGraph = Graph.test(
            workspace: Workspace.test(
                schemes: [
                    schemeA,
                ]
            ),
            projects: [project],
            targets: [
                project.path: [
                    frameworkA,
                    unitTestsA,
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
                    FileDescriptor(path: testsCacheDirectory.appending(component: "FrameworkA"))
                ),
                .file(
                    FileDescriptor(path: testsCacheDirectory.appending(component: "UnitTestsA"))
                ),
            ]
        )
    }
}
