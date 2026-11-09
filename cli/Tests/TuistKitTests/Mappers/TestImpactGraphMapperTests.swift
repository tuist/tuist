import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistGit
import TuistServer
import XcodeGraph
@testable import TuistKit

struct TestImpactGraphMapperTests {
    private let gitController = MockGitControlling()
    private let resolveBaselineService = MockResolveTestImpactBaselineServicing()
    private let createRunService = MockCreateTestImpactRunServicing()
    private let path = try! AbsolutePath(validating: "/repo")
    private let subject = TestImpactGraphMapper(testPlan: nil, schemeName: nil, includedTargets: [], excludedTargets: [])
    private let selector: TestImpactSelector

    init() {
        selector = TestImpactSelector(
            invocation: TestImpactSelector.Invocation(
                fullHandle: "acme/shop",
                serverURL: URL(string: "https://tuist.dev")!,
                path: path,
                scheme: nil,
                testPlan: nil,
                destination: nil,
                platform: nil
            ),
            gitController: gitController,
            resolveBaselineService: resolveBaselineService,
            createRunService: createRunService
        )
        given(gitController).isInGitRepository(workingDirectory: .any).willReturn(true)
        given(gitController).topLevelGitDirectory(workingDirectory: .any).willReturn(path)
        given(gitController).gitInfo(workingDirectory: .any)
            .willReturn(.test(branch: "feature", sha: "head", pullRequestNumber: 7))
        given(gitController).checkedOutCommit(workingDirectory: .any)
            .willReturn(GitCheckedOutCommit(sha: "head", parentSHAs: []))
        given(gitController).hasUncommittedChanges(workingDirectory: .any).willReturn(false)
    }

    @Test func leaves_the_graph_alone_without_a_selector() async throws {
        let (graph, _) = graphs(hashMatched: ["AppTests"])

        let (gotGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        #expect(gotGraph == graph)
    }

    @Test func prunes_the_modules_with_no_selected_test() async throws {
        let (graph, environment) = graphs(hashMatched: ["AppTests"])
        given(resolveBaselineService).resolveTestImpactBaseline(
            fullHandle: .any, serverURL: .any, commitSHA: .any, parentSHAs: .any, ancestorSHAs: .any,
            platform: .any, scheme: .any, testPlan: .any, destination: .any
        ).willReturn(.baseline(sha: "baseline", diffCached: true))
        given(createRunService).createTestImpactRun(fullHandle: .any, serverURL: .any, request: .any)
            .willReturn(.selected(TestImpactSelection(
                runID: "run",
                requested: 3,
                selected: 1,
                skipped: 2,
                skippedTests: [
                    SkippedTest(module: "CatalogTests", suite: nil, name: nil),
                    SkippedTest(module: "CoreTests", suite: "MoneyTests", name: "testAdd()"),
                ]
            )))

        let (gotGraph, _, _) = try await TestImpactSelector.$current.withValue(selector) {
            try await subject.map(graph: graph, environment: environment)
        }

        #expect(prunableTargetNames(gotGraph) == ["AppTests", "CatalogTests", "UITests"])
        verify(createRunService).createTestImpactRun(
            fullHandle: .any,
            serverURL: .any,
            request: .matching {
                // `UITests` was prunable before hashing, so it isn't one of the modules hashing skipped.
                $0.modules == ["CatalogTests", "CoreTests"] && $0.skippedModules == ["AppTests"] && $0.platform == "ios"
            }
        ).called(1)
    }

    @Test func leaves_the_graph_as_hashing_left_it_on_a_fallback() async throws {
        let (graph, environment) = graphs(hashMatched: ["AppTests"])
        given(resolveBaselineService).resolveTestImpactBaseline(
            fullHandle: .any, serverURL: .any, commitSHA: .any, parentSHAs: .any, ancestorSHAs: .any,
            platform: .any, scheme: .any, testPlan: .any, destination: .any
        ).willReturn(.unavailable(.noBaseline))
        given(createRunService).createTestImpactRun(fullHandle: .any, serverURL: .any, request: .any)
            .willReturn(.fallback(runID: "run", reason: .noBaseline, matchedPath: nil))

        let (gotGraph, _, gotEnvironment) = try await TestImpactSelector.$current.withValue(selector) {
            try await subject.map(graph: graph, environment: environment)
        }

        #expect(gotGraph == graph)
        #expect(prunableTargetNames(gotGraph) == ["AppTests", "UITests"])
        #expect(gotEnvironment.targetTestCacheItems == environment.targetTestCacheItems)
    }

    @Test func records_what_hashing_skipped_and_keeps_the_graph_when_every_target_matched() async throws {
        let (graph, environment) = graphs(hashMatched: ["AppTests", "CatalogTests", "CoreTests"])
        given(resolveBaselineService).resolveTestImpactBaseline(
            fullHandle: .any, serverURL: .any, commitSHA: .any, parentSHAs: .any, ancestorSHAs: .any,
            platform: .any, scheme: .any, testPlan: .any, destination: .any
        ).willReturn(.unavailable(.noBaseline))
        given(createRunService).createTestImpactRun(fullHandle: .any, serverURL: .any, request: .any)
            .willReturn(.fallback(runID: "run", reason: .noBaseline, matchedPath: nil))

        let (gotGraph, _, gotEnvironment) = try await TestImpactSelector.$current.withValue(selector) {
            try await subject.map(graph: graph, environment: environment)
        }

        #expect(gotGraph == graph)
        #expect(gotEnvironment.targetTestCacheItems == environment.targetTestCacheItems)
        verify(createRunService).createTestImpactRun(
            fullHandle: .any,
            serverURL: .any,
            request: .matching { $0.modules == [] && $0.skippedModules == ["AppTests", "CatalogTests", "CoreTests"] }
        ).called(1)
    }

    /// A graph after selective testing tagged `hashMatched`, and the environment it left: the graph
    /// before hashing as `initialGraph`, with `UITests` already prunable, and the hash hits.
    private func graphs(hashMatched: Set<String>) -> (Graph, MapperEnvironment) {
        func project(prunable: Set<String>) -> Project {
            Project.test(path: path, targets: [
                Target.test(name: "App", destinations: [.iPhone], product: .app),
            ] + ["AppTests", "CoreTests", "CatalogTests"].map {
                Target.test(
                    name: $0,
                    destinations: [.iPhone],
                    product: .unitTests,
                    metadata: .test(tags: prunable.contains($0) ? ["tuist:prunable"] : [])
                )
            } + [
                Target.test(
                    name: "UITests",
                    destinations: [.iPhone],
                    product: .uiTests,
                    metadata: .test(tags: ["tuist:prunable"])
                ),
            ])
        }
        let initialProject = project(prunable: [])
        let hashedProject = project(prunable: hashMatched)
        var environment = MapperEnvironment()
        environment.initialGraph = Graph.test(projects: [path: initialProject])
        environment.targetTestCacheItems = [
            path: Dictionary(uniqueKeysWithValues: hashMatched.map {
                ($0, CacheItem(name: $0, hash: "hash", source: .local, cacheCategory: .selectiveTests))
            }),
        ]
        return (Graph.test(projects: [path: hashedProject]), environment)
    }

    private func prunableTargetNames(_ graph: Graph) -> [String] {
        graph.projects.values.flatMap(\.targets.values)
            .filter { $0.metadata.tags.contains("tuist:prunable") }
            .map(\.name)
            .sorted()
    }
}
