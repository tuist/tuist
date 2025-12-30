import FileSystem
import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistHasher
import XcodeGraph

@testable import TuistKit

#if canImport(TuistCacheEE)
    import TuistCacheEE

    @Suite
    struct SelectiveTestingGraphHasherTests {
        private let fileSystem = FileSystem()
        private let graphContentHasher = MockGraphContentHashing()
        private let subject: SelectiveTestingGraphHasher
        init() {
            subject = SelectiveTestingGraphHasher(
                graphContentHasher: graphContentHasher
            )
        }

        @Test func test_hash() async throws {
            try await fileSystem.runInTemporaryDirectory(prefix: "SelectiveTestingGraphHasherTests") { temporaryPath in
                // Given
                let targetA: Target = .test(
                    name: "TargetA"
                )
                let targetAUnitTests: Target = .test(
                    name: "TargetAUnitTests",
                    product: .unitTests,
                    dependencies: [
                        .target(
                            name: "TargetA",
                            status: .required,
                            condition: nil
                        ),
                    ]
                )
                let app: Target = .test(
                    name: "App",
                    product: .app
                )
                let project: Project = .test(
                    targets: [
                        targetA,
                        targetAUnitTests,
                        app,
                    ]
                )

                let graph: Graph = .test(
                    projects: [
                        temporaryPath: project,
                    ],
                    dependencies: [
                        .target(name: "TargetAUnitTests", path: temporaryPath, status: .required): [
                            .target(name: "TargetA", path: temporaryPath, status: .required),
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
                    .willReturn(
                        [
                            GraphTarget(path: temporaryPath, target: targetA, project: project): .test(hash: "hash-a"),
                        ]
                    )

                // When
                let got = try await subject.hash(
                    graph: graph,
                    additionalStrings: [
                        "additional-string-a",
                    ]
                )

                // Then
                verify(graphContentHasher)
                    .contentHashes(
                        for: .any,
                        include: .matching { include in
                            include(GraphTarget(path: temporaryPath, target: targetA, project: project)) &&
                                include(GraphTarget(path: temporaryPath, target: targetAUnitTests, project: project)) &&
                                !include(GraphTarget(path: temporaryPath, target: app, project: project))

                        },
                        destination: .any,
                        additionalStrings: .value(["additional-string-a"])
                    )
                    .called(1)
                #expect(
                    got == [
                        GraphTarget(path: temporaryPath, target: targetA, project: project): .test(hash: "hash-a"),
                    ]
                )
            }
        }
    }

    @Suite
    struct SelectiveTestingServiceTests {
        private let subject = SelectiveTestingService()

        @Test func test_cachedTests() async throws {
            // Given
            let targetA: Target = .test(
                name: "TargetA"
            )
            let targetAUnitTests: Target = .test(
                name: "TargetAUnitTests",
                product: .unitTests,
                dependencies: [
                    .target(
                        name: "TargetA",
                        status: .required,
                        condition: nil
                    ),
                ]
            )
            let targetB: Target = .test(
                name: "TargetB"
            )
            let targetBUnitTests: Target = .test(
                name: "TargetBUnitTests",
                product: .unitTests,
                dependencies: [
                    .target(
                        name: "TargetB",
                        status: .required,
                        condition: nil
                    ),
                ]
            )
            let projectPath = try AbsolutePath(validating: "/tmp/Project")
            let schemeA: Scheme = .test(
                name: "SchemeA",
                testAction: .test(
                    targets: [
                        TestableTarget(target: TargetReference(projectPath: projectPath, name: "TargetAUnitTests")),
                        TestableTarget(target: TargetReference(projectPath: projectPath, name: "TargetBUnitTests")),
                    ]
                )
            )
            let project: Project = .test(
                targets: [
                    targetA,
                    targetAUnitTests,
                    targetB,
                    targetBUnitTests,
                ],
                schemes: [
                    schemeA,
                ]
            )
            let targetAUnitTestsGraphTarget = GraphTarget(
                path: projectPath,
                target: targetAUnitTests,
                project: project
            )
            let targetBUnitTestsGraphTarget = GraphTarget(
                path: projectPath,
                target: targetBUnitTests,
                project: project
            )

            // When
            let got = try await subject.cachedTests(
                testableGraphTargets: [
                    targetAUnitTestsGraphTarget,
                    targetBUnitTestsGraphTarget,
                ],
                selectiveTestingHashes: [
                    GraphTarget(
                        path: projectPath,
                        target: targetAUnitTests,
                        project: project
                    ): "hash-a-unit-tests",
                    GraphTarget(
                        path: projectPath,
                        target: targetBUnitTests,
                        project: project
                    ): "hash-b-unit-tests",
                ],
                selectiveTestingCacheItems: [
                    CacheItem(
                        name: "TargetAUnitTests",
                        hash: "hash-a-unit-tests",
                        source: .remote,
                        cacheCategory: .selectiveTests
                    ),
                ]
            )

            // Then
            let targetAUnitTestsIdentifier = try TestIdentifier(target: "TargetAUnitTests")
            #expect(
                got.sorted(by: { $0.description > $1.description }) == [
                    targetAUnitTestsIdentifier,
                ]
            )
        }
    }

#endif
