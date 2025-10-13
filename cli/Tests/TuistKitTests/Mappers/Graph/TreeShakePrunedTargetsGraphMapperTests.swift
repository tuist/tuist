import Foundation
import Path
import XcodeGraph
import XCTest
@testable import TuistCore
@testable import TuistKit
@testable import TuistTesting

final class TreeShakePrunedTargetsGraphMapperTests: TuistUnitTestCase {
    var subject: TreeShakePrunedTargetsGraphMapper!

    override func setUp() {
        super.setUp()
        subject = TreeShakePrunedTargetsGraphMapper()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_map_removes_projects_when_all_its_targets_are_pruned() throws {
        // Given
        let target = Target.test(metadata: .metadata(tags: ["tuist:prunable"]))
        let project = Project.test(targets: [target])

        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project]
        )

        let expectedGraph = Graph.test(
            path: project.path,
            projects: [:]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertEqual(
            gotGraph,
            expectedGraph
        )
    }

    func test_map_removes_pruned_targets_from_projects() throws {
        // Given
        let firstTarget = Target.test(name: "first")
        let secondTarget = Target.test(name: "second", metadata: .metadata(tags: ["tuist:prunable"]))
        let project = Project.test(targets: [firstTarget, secondTarget])

        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            dependencies: [:]
        )

        // When
        let (gotGraph, gotValueSideEffects, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEmpty(gotValueSideEffects)
        XCTAssertEqual(gotGraph.projects.count, 1)
        let valueTargets = gotGraph.projects.values.flatMap(\.targets.values).sorted()
        XCTAssertEqual(valueTargets.count, 1)
        XCTAssertEqual(valueTargets.first, firstTarget)
    }

    func test_map_removes_project_schemes_with_whose_all_targets_have_been_removed() throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let prunedTarget = Target.test(name: "first", metadata: .metadata(tags: ["tuist:prunable"]))
        let keptTarget = Target.test(name: "second")
        let schemes: [Scheme] = [
            .test(buildAction: .test(targets: [.init(projectPath: path, name: prunedTarget.name)])),
        ]
        let project = Project.test(path: path, targets: [prunedTarget, keptTarget], schemes: schemes)

        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            dependencies: [:]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertNotEmpty(gotGraph.projects)
        XCTAssertEmpty(gotGraph.projects.values.flatMap(\.schemes))
    }

    func test_map_removes_project_schemes_with_whose_run_action_expand_variable_from_target_has_been_removed() throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let prunedTarget = Target.test(name: "first", metadata: .metadata(tags: ["tuist:prunable"]))
        let keptTarget = Target.test(name: "second", prune: false)
        let schemes: [Scheme] = [
            .test(
                buildAction: .test(targets: [.init(projectPath: path, name: keptTarget.name)]),
                runAction: .test(expandVariableFromTarget: .init(projectPath: path, name: prunedTarget.name))
            ),
        ]
        let project = Project.test(path: path, targets: [prunedTarget, keptTarget], schemes: schemes)

        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            dependencies: [:]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertNotEmpty(gotGraph.projects)
        XCTAssertEmpty(gotGraph.projects.values.flatMap(\.schemes))
    }

    func test_map_removes_project_schemes_with_whose_test_action_expand_variable_from_target_has_been_removed() throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let prunedTarget = Target.test(name: "first", metadata: .metadata(tags: ["tuist:prunable"]))
        let keptTarget = Target.test(name: "second")
        let schemes: [Scheme] = [
            .test(
                buildAction: .test(targets: [.init(projectPath: path, name: keptTarget.name)]),
                testAction: .test(expandVariableFromTarget: .init(projectPath: path, name: prunedTarget.name))
            ),
        ]
        let project = Project.test(path: path, targets: [prunedTarget, keptTarget], schemes: schemes)

        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            dependencies: [:]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertNotEmpty(gotGraph.projects)
        XCTAssertEmpty(gotGraph.projects.values.flatMap(\.schemes))
    }

    func test_map_removes_project_schemes_with_test_plans_when_all_targets_were_removed() throws {
        let path = try AbsolutePath(validating: "/project")
        let prunedTarget = Target.test(name: "first", metadata: .metadata(tags: ["tuist:prunable"]))
        let keptTarget = Target.test(name: "second")
        let schemes: [Scheme] = [
            .test(
                buildAction: .test(targets: [.init(projectPath: path, name: prunedTarget.name)]),
                testAction: .test(
                    testPlans: [
                        TestPlan(
                            path: "/Test.xctestplan",
                            testTargets: [
                                .test(
                                    target: TargetReference(
                                        projectPath: path,
                                        name: prunedTarget.name
                                    )
                                ),
                            ],
                            isDefault: true
                        ),
                    ]
                )
            ),
        ]
        let project = Project.test(path: path, targets: [keptTarget, prunedTarget], schemes: schemes)

        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            dependencies: [:]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertNotEmpty(gotGraph.projects)
        XCTAssertEmpty(gotGraph.projects.values.flatMap(\.schemes))
    }

    func test_map_keeps_project_schemes_with_whose_all_targets_have_been_removed_but_have_test_plans() throws {
        let path = try AbsolutePath(validating: "/project")
        let prunedTarget = Target.test(name: "first", metadata: .metadata(tags: ["tuist:prunable"]))
        let keptTarget = Target.test(name: "second")
        let schemes: [Scheme] = [
            .test(
                buildAction: .test(targets: [.init(projectPath: path, name: prunedTarget.name)]),
                testAction: .test(
                    testPlans: [
                        TestPlan(
                            path: "/Test.xctestplan",
                            testTargets: [
                                .test(
                                    target: TargetReference(
                                        projectPath: path,
                                        name: prunedTarget.name
                                    )
                                ),
                                .test(
                                    target: TargetReference(
                                        projectPath: path,
                                        name: keptTarget.name
                                    )
                                ),
                            ],
                            isDefault: true
                        ),
                    ]
                )
            ),
        ]
        let project = Project.test(path: path, targets: [prunedTarget, keptTarget], schemes: schemes)

        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            dependencies: [:]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertNotEmpty(gotGraph.projects)
        XCTAssertEqual(
            gotGraph.projects.values.flatMap(\.schemes),
            [
                .test(
                    buildAction: .test(targets: []),
                    testAction: .test(
                        targets: [],
                        testPlans: [
                            TestPlan(
                                path: "/Test.xctestplan",
                                testTargets: [
                                    .test(
                                        target: TargetReference(
                                            projectPath: path,
                                            name: keptTarget.name
                                        )
                                    ),
                                ],
                                isDefault: true
                            ),
                        ]
                    )
                ),
            ]
        )
    }

    func test_map_removes_the_workspace_projects_that_no_longer_exist() throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let removedProjectPath = AbsolutePath.root.appending(component: "Other")
        let target = Target.test(name: "first", metadata: .metadata(tags: ["tuist:prunable"]))
        let schemes: [Scheme] = [
            .test(buildAction: .test(targets: [.init(projectPath: path, name: target.name)])),
        ]
        let project = Project.test(path: path, targets: [target], schemes: schemes)
        let workspace = Workspace.test(
            path: path,
            projects: [project.path, removedProjectPath]
        )

        // Given
        let graph = Graph.test(
            path: project.path,
            workspace: workspace,
            projects: [project.path: project],
            dependencies: [:]
        )

        // When
        let (gotGraph, _, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertFalse(gotGraph.workspace.projects.contains(removedProjectPath))
    }

    func test_map_treeshakes_the_workspace_schemes() throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let removedProjectPath = AbsolutePath.root.appending(component: "Other")
        let target = Target.test(name: "first", metadata: .metadata(tags: ["tuist:prunable"]))
        let schemes: [Scheme] = [
            .test(buildAction: .test(targets: [.init(projectPath: path, name: target.name)])),
        ]
        let project = Project.test(path: path, targets: [target], schemes: [])
        let workspace = Workspace.test(
            path: path,
            projects: [project.path, removedProjectPath],
            schemes: schemes
        )

        let graph = Graph.test(
            path: project.path,
            workspace: workspace,
            projects: [project.path: project],
            dependencies: [:]
        )

        // When
        let (gotGraph, _, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEmpty(gotGraph.workspace.schemes)
    }

    func test_map_removes_pruned_targets_from_scheme() throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let targets = [
            Target.test(name: "first", prune: true),
            Target.test(name: "second", prune: false),
            Target.test(name: "third", prune: true),
        ]
        let scheme = Scheme.test(
            name: "Scheme",
            buildAction: .test(targets: targets.map { TargetReference(projectPath: path, name: $0.name) }),
            testAction: .test(
                targets: targets.map { TestableTarget(target: TargetReference(projectPath: path, name: $0.name)) },
                coverage: true,
                codeCoverageTargets: targets.map { TargetReference(projectPath: path, name: $0.name) }
            )
        )
        let project = Project.test(path: path, targets: targets, schemes: [scheme])
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project]
        )

        let unprunedTargets = targets.filter { !$0.metadata.tags.contains("tuist:prunable") }
        let schemeWithUnprunedTargets = Scheme.test(
            name: "Scheme",
            buildAction: .test(targets: unprunedTargets.map { TargetReference(projectPath: path, name: $0.name) }),
            testAction: .test(
                targets: unprunedTargets.map { TestableTarget(target: TargetReference(projectPath: path, name: $0.name)) },
                coverage: true,
                codeCoverageTargets: unprunedTargets.map { TargetReference(projectPath: path, name: $0.name) }
            )
        )
        let expectedProject = Project.test(path: path, targets: unprunedTargets, schemes: [schemeWithUnprunedTargets])
        let expectedGraph = Graph.test(
            path: expectedProject.path,
            projects: [expectedProject.path: expectedProject]
        )

        // When
        let (gotGraph, _, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEqual(gotGraph, expectedGraph)
    }

    func test_map_preserves_target_order_in_projects() throws {
        // Given
        let firstTarget = Target.test(name: "Brazil")
        let secondTarget = Target.test(name: "Ghana")
        let thirdTarget = Target.test(name: "Japan")
        let prunedTarget = Target.test(name: "Pruned", metadata: .metadata(tags: ["tuist:prunable"]))
        let project = Project.test(targets: [firstTarget, secondTarget, thirdTarget, prunedTarget])

        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            dependencies: [:]
        )

        let expectedProject = Project.test(targets: [firstTarget, secondTarget, thirdTarget])

        // When
        let (gotGraph, _, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEqual(gotGraph.projects.first?.value, expectedProject)
    }

    func test_map_preserves_schemes_with_no_targets_but_executables() throws {
        // Given
        let project = Project.test(targets: [])
        let executable = try AbsolutePath(validating: "/test/tuist")

        let graph = Graph.test(
            path: project.path,
            workspace: .test(schemes: [
                .test(name: "Tuist", runAction: .test(filePath: executable)),
            ]),
            projects: [project.path: project],
            dependencies: [:]
        )

        // When
        let (gotGraph, _, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEqual(gotGraph.workspace.schemes.count, 1)
        XCTAssertEqual(gotGraph.workspace.schemes.first?.name, "Tuist")
    }

    func test_map_removes_pruned_dependencies() throws {
        // Given
        let frameworkBiOS = Target.test(name: "BiOS", destinations: [.iPhone], product: .framework)
        // This one has been marked to prune by Tuist because it's not needed if we filter down the platforms from the entry-point
        // nodes of the graph.
        let frameworkBtvOS = Target.test(
            name: "BtvOS",
            destinations: [.appleTv],
            product: .framework,
            metadata: .metadata(tags: ["tuist:prunable"])
        )
        let frameworkA = Target.test(name: "A", destinations: [.iPhone], product: .framework, dependencies: [
            .target(name: frameworkBiOS.name, status: .required, condition: nil),
            .target(name: frameworkBtvOS.name, status: .required, condition: nil),
        ])
        let app = Target.test(name: "App", destinations: [.iPhone], product: .app, dependencies: [
            .target(name: frameworkA.name, status: .required, condition: nil),
        ])

        let project = Project.test(targets: [app, frameworkA, frameworkBiOS, frameworkBtvOS])

        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            dependencies: [
                .target(name: app.name, path: project.path): Set([.target(name: frameworkA.name, path: project.path)]),
                .target(name: frameworkA.name, path: project.path): Set([
                    .target(name: frameworkBiOS.name, path: project.path),
                    .target(name: frameworkBtvOS.name, path: project.path),
                ]),
            ],
            dependencyConditions: [
                GraphEdge(
                    from: .target(name: frameworkA.name, path: project.path),
                    to: .target(name: frameworkBiOS.name, path: project.path)
                ): try .test([.ios])!,
                GraphEdge(
                    from: .target(name: frameworkA.name, path: project.path),
                    to: .target(name: frameworkBtvOS.name, path: project.path)
                ): try .test([.tvos])!,
            ]
        )

        // When
        let (gotGraph, _, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let expectedFrameworkBiOS = Target.test(name: "BiOS", destinations: [.iPhone], product: .framework)
        let expectedFrameworkA = Target.test(name: "A", destinations: [.iPhone], product: .framework, dependencies: [
            .target(name: expectedFrameworkBiOS.name, status: .required, condition: nil),
        ])
        let expectedApp = Target.test(name: "App", destinations: [.iPhone], product: .app, dependencies: [
            .target(name: expectedFrameworkA.name, status: .required, condition: nil),
        ])
        let expectedProject = Project.test(targets: [expectedApp, expectedFrameworkA, expectedFrameworkBiOS])

        let expectedGraph = Graph.test(
            path: expectedProject.path,
            projects: [expectedProject.path: expectedProject],
            dependencies: [
                .target(name: app.name, path: project.path): Set([.target(name: frameworkA.name, path: project.path)]),
                .target(name: frameworkA.name, path: project.path): Set([.target(name: frameworkBiOS.name, path: project.path)]),
            ],
            dependencyConditions: [
                GraphEdge(
                    from: .target(name: frameworkA.name, path: project.path),
                    to: .target(name: frameworkBiOS.name, path: project.path)
                ): try .test([.ios])!,
                GraphEdge(
                    from: .target(name: frameworkA.name, path: project.path),
                    to: .target(name: frameworkBtvOS.name, path: project.path)
                ): try .test([.tvos])!,
            ]
        )
        XCTAssertBetterEqual(expectedGraph, gotGraph)
    }
}
