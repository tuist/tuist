import Path
import Testing
import TuistCore
import XcodeGraph

@testable import TuistCache

struct CacheWarmTargetGraphSelectorTests {
    @Test
    func selection_when_no_requested_targets_returns_allReachable() {
        let graphTraverser = GraphTraverser(graph: makeGraph())

        let selection = CacheWarmTargetGraphSelector.selection(
            graphTraverser: graphTraverser,
            requestedTargets: []
        )

        #expect(selection == .allReachable)
    }

    @Test
    func selection_when_requested_targets_include_tests_keeps_only_non_test_branches() {
        let graph = makeGraph()
        let graphTraverser = GraphTraverser(graph: graph)
        let localPath = try! AbsolutePath(validating: "/Local") // swiftlint:disable:this force_try
        let localProject = graph.projects[localPath]!
        let expectedTargets: Set<GraphTarget> = [
            GraphTarget(path: localPath, target: localProject.targets["App"]!, project: localProject),
            GraphTarget(path: localPath, target: localProject.targets["AppCore"]!, project: localProject),
        ]

        let selection = CacheWarmTargetGraphSelector.selection(
            graphTraverser: graphTraverser,
            requestedTargets: ["App", "AppUITests"]
        )

        #expect(selection == .explicit(expectedTargets))
    }

    @Test
    func selection_when_requested_targets_are_only_tests_returns_noNonTestRoots() {
        let graphTraverser = GraphTraverser(graph: makeGraph())

        let selection = CacheWarmTargetGraphSelector.selection(
            graphTraverser: graphTraverser,
            requestedTargets: ["AppUITests"]
        )

        #expect(selection == .noNonTestRoots)
    }

    private func makeGraph() -> Graph {
        let localPath = try! AbsolutePath(validating: "/Local") // swiftlint:disable:this force_try
        let externalPath = try! AbsolutePath(validating: "/External") // swiftlint:disable:this force_try

        let appCore = Target.test(name: "AppCore", product: .framework)
        let app = Target.test(
            name: "App",
            product: .app,
            dependencies: [.target(name: appCore.name)]
        )
        let buildingDetailsMocks = Target.test(
            name: "BuildingDetailsMocks",
            product: .framework,
            dependencies: [.project(target: "ApolloTestSupport", path: externalPath)]
        )
        let appUITests = Target.test(
            name: "AppUITests",
            product: .uiTests,
            dependencies: [
                .target(name: app.name),
                .target(name: buildingDetailsMocks.name),
            ]
        )

        let localProject = Project.test(
            path: localPath,
            name: "Local",
            targets: [app, appCore, buildingDetailsMocks, appUITests]
        )

        let apolloAPI = Target.test(name: "ApolloAPI", product: .staticFramework)
        let apolloTestSupport = Target.test(
            name: "ApolloTestSupport",
            product: .staticFramework,
            dependencies: [.target(name: apolloAPI.name)]
        )
        let externalProject = Project.test(
            path: externalPath,
            name: "Apollo",
            targets: [apolloAPI, apolloTestSupport],
            type: .external(hash: "apollo")
        )

        return Graph.test(
            path: localPath,
            projects: [
                localPath: localProject,
                externalPath: externalProject,
            ],
            dependencies: [
                .target(name: app.name, path: localPath): [
                    .target(name: appCore.name, path: localPath),
                ],
                .target(name: buildingDetailsMocks.name, path: localPath): [
                    .target(name: apolloTestSupport.name, path: externalPath),
                ],
                .target(name: appUITests.name, path: localPath): [
                    .target(name: app.name, path: localPath),
                    .target(name: buildingDetailsMocks.name, path: localPath),
                ],
                .target(name: apolloTestSupport.name, path: externalPath): [
                    .target(name: apolloAPI.name, path: externalPath),
                ],
            ]
        )
    }
}
