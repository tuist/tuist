import Foundation
import Path
import Testing
import XcodeGraph
@testable import TuistCore
@testable import TuistGenerator

struct SchemeTargetQueriesGraphMapperTests {
    private let subject = SchemeTargetQueriesGraphMapper()

    private let featurePath = try! AbsolutePath(validating: "/Features/Home") // swiftlint:disable:this force_try
    private let frameworkPath = try! AbsolutePath(validating: "/Frameworks/Network") // swiftlint:disable:this force_try

    /// A graph of two projects, each one with a framework, a unit test and a screenshot test target.
    private func graph(workspaceSchemes: [Scheme] = [], projectSchemes: [Scheme] = []) -> Graph {
        let projects = [
            featurePath: Project.test(
                path: featurePath,
                targets: [
                    Target.test(name: "HomeFeature", product: .framework),
                    Target.test(name: "HomeFeature-UnitTests", product: .unitTests),
                    Target.test(
                        name: "HomeFeature-ScreenshotTests",
                        product: .unitTests,
                        metadata: .test(tags: ["screenshot-tests"])
                    ),
                ],
                schemes: projectSchemes
            ),
            frameworkPath: Project.test(
                path: frameworkPath,
                targets: [
                    Target.test(name: "NetworkKit", product: .framework),
                    Target.test(name: "NetworkKit-UnitTests", product: .unitTests),
                    Target.test(
                        name: "NetworkKit-ScreenshotTests",
                        product: .unitTests,
                        metadata: .test(tags: ["screenshot-tests"])
                    ),
                ]
            ),
        ]

        return Graph.test(
            workspace: .test(projects: Array(projects.keys), schemes: workspaceSchemes),
            projects: projects
        )
    }

    @Test func resolvesTestActionQueriesAcrossProjects() async throws {
        // Given
        let graph = graph(workspaceSchemes: [
            Scheme.test(
                name: "AllUnitTests",
                testAction: .test(
                    targets: [],
                    targetQueries: [TestableTargetQuery(query: .matching(pattern: "*-UnitTests"), parallelization: .all)]
                )
            ),
        ])

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let testAction = try #require(mappedGraph.workspace.schemes.first?.testAction)
        #expect(testAction.targets.map(\.target) == [
            TargetReference(projectPath: featurePath, name: "HomeFeature-UnitTests"),
            TargetReference(projectPath: frameworkPath, name: "NetworkKit-UnitTests"),
        ])
        #expect(testAction.targets.allSatisfy { $0.parallelization == .all })
        #expect(testAction.targetQueries.isEmpty)
    }

    @Test func resolvesTaggedTestActionQueries() async throws {
        // Given
        let graph = graph(workspaceSchemes: [
            Scheme.test(
                name: "AllScreenshotTests",
                testAction: .test(
                    targets: [],
                    targetQueries: [TestableTargetQuery(query: .tagged("screenshot-tests"))]
                )
            ),
        ])

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let testAction = try #require(mappedGraph.workspace.schemes.first?.testAction)
        #expect(testAction.targets.map(\.target.name) == ["HomeFeature-ScreenshotTests", "NetworkKit-ScreenshotTests"])
    }

    @Test func doesNotMatchNonTestTargetsInTestActions() async throws {
        // Given
        let graph = graph(workspaceSchemes: [
            Scheme.test(
                name: "AllTests",
                testAction: .test(
                    targets: [],
                    targetQueries: [TestableTargetQuery(query: .matching(pattern: "*"))]
                )
            ),
        ])

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let testAction = try #require(mappedGraph.workspace.schemes.first?.testAction)
        #expect(testAction.targets.map(\.target.name) == [
            "HomeFeature-ScreenshotTests",
            "HomeFeature-UnitTests",
            "NetworkKit-ScreenshotTests",
            "NetworkKit-UnitTests",
        ])
    }

    @Test func keepsExplicitlyListedTargetsAndDoesNotDuplicateThem() async throws {
        // Given
        let explicitTarget = TestableTarget(
            target: TargetReference(projectPath: frameworkPath, name: "NetworkKit-UnitTests"),
            skipped: true
        )
        let graph = graph(workspaceSchemes: [
            Scheme.test(
                name: "AllUnitTests",
                testAction: .test(
                    targets: [explicitTarget],
                    targetQueries: [TestableTargetQuery(query: .matching(pattern: "*-UnitTests"))]
                )
            ),
        ])

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let testAction = try #require(mappedGraph.workspace.schemes.first?.testAction)
        #expect(testAction.targets == [
            explicitTarget,
            TestableTarget(target: TargetReference(projectPath: featurePath, name: "HomeFeature-UnitTests")),
        ])
    }

    @Test func resolvesBuildActionQueries() async throws {
        // Given
        let graph = graph(workspaceSchemes: [
            Scheme.test(
                name: "AllFrameworks",
                buildAction: BuildAction(targets: [], targetQueries: [.matching(pattern: "*Kit")]),
                testAction: nil
            ),
        ])

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let buildAction = try #require(mappedGraph.workspace.schemes.first?.buildAction)
        #expect(buildAction.targets == [TargetReference(projectPath: frameworkPath, name: "NetworkKit")])
        #expect(buildAction.targetQueries.isEmpty)
    }

    @Test func resolvesQueriesOfProjectSchemes() async throws {
        // Given
        let graph = graph(projectSchemes: [
            Scheme.test(
                name: "HomeFeatureTests",
                testAction: .test(
                    targets: [],
                    targetQueries: [TestableTargetQuery(query: .matching(pattern: "HomeFeature-*"))]
                )
            ),
        ])

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let testAction = try #require(mappedGraph.projects[featurePath]?.schemes.first?.testAction)
        #expect(testAction.targets.map(\.target.name) == ["HomeFeature-ScreenshotTests", "HomeFeature-UnitTests"])
    }

    @Test func leavesSchemesWithoutQueriesUntouched() async throws {
        // Given
        let scheme = Scheme.test(
            name: "HomeFeature",
            buildAction: BuildAction(targets: [TargetReference(projectPath: featurePath, name: "HomeFeature")]),
            testAction: nil
        )
        let graph = graph(workspaceSchemes: [scheme])

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        #expect(mappedGraph.workspace.schemes == [scheme])
    }
}
