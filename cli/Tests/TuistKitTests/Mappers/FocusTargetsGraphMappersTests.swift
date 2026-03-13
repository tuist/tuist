import Foundation
import TuistCore
import TuistTesting
import XcodeGraph
import XCTest
@testable import TuistKit

final class FocusTargetsGraphMappersTests: TuistUnitTestCase {
    func test_map_when_included_targets_is_empty_no_targets_are_pruned() throws {
        // Given
        let targetNames = ["foo", "bar", "baz"].shuffled()
        let aTarget = Target.test(name: targetNames[0])
        let bTarget = Target.test(name: targetNames[1])
        let cTarget = Target.test(name: targetNames[2])
        let subject = FocusTargetsGraphMappers(includedTargets: Set())
        let path = try temporaryPath()
        let project = Project.test(path: path, targets: [aTarget, bTarget, cTarget])
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: bTarget.name, path: path): [
                    .target(name: aTarget.name, path: path),
                ],
                .target(name: cTarget.name, path: path): [
                    .target(name: bTarget.name, path: path),
                ],
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try subject.map(graph: graph, environment: MapperEnvironment())
        let pruningTargets = gotGraph.projects.values.flatMap(\.targets.values).sorted()
            .filter { $0.metadata.tags.contains("tuist:prunable") }

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertEmpty(pruningTargets.map(\.name))
    }

    func test_map_when_included_targets_is_empty_no_internal_targets_are_pruned() throws {
        // Given
        let targetNames = ["foo", "bar", "baz", "lorem", "ipsum"].shuffled()
        let aTarget = Target.test(name: targetNames[0])
        let bTarget = Target.test(name: targetNames[1])
        let cTarget = Target.test(name: targetNames[2])
        let dTarget = Target.test(name: targetNames[3])
        let eTarget = Target.test(name: targetNames[4])
        let subject = FocusTargetsGraphMappers(includedTargets: Set())
        let projectPath = try temporaryPath().appending(component: "Project")
        let externalProjectPath = try temporaryPath().appending(component: "ExternalProject")
        let project = Project.test(path: projectPath, targets: [aTarget, bTarget, cTarget])
        let externalProject = Project.test(path: externalProjectPath, targets: [dTarget, eTarget], type: .external(hash: nil))
        let graph = Graph.test(
            projects: [
                project.path: project,
                externalProject.path: externalProject,
            ],
            dependencies: [
                .target(name: bTarget.name, path: projectPath): [
                    .target(name: aTarget.name, path: projectPath),
                ],
                .target(name: cTarget.name, path: projectPath): [
                    .target(name: bTarget.name, path: projectPath),
                ],
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try subject.map(graph: graph, environment: MapperEnvironment())
        let pruningTargets = gotGraph.projects.values.flatMap(\.targets.values).sorted()
            .filter { $0.metadata.tags.contains("tuist:prunable") }
        let expectingTargets = [dTarget, eTarget]

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertEqual(
            pruningTargets.map(\.name).sorted(),
            expectingTargets.map(\.name).sorted()
        )
    }

    func test_map_when_included_targets_is_target_with_no_dependency_all_other_targets_are_pruned() throws {
        // Given
        let targetNames = ["foo", "bar", "baz"].shuffled()
        let aTarget = Target.test(name: targetNames[0])
        let bTarget = Target.test(name: targetNames[1])
        let cTarget = Target.test(name: targetNames[2])
        let subject = FocusTargetsGraphMappers(includedTargets: [.named(aTarget.name)])
        let path = try temporaryPath()
        let project = Project.test(path: path, targets: [aTarget, bTarget, cTarget])
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: bTarget.name, path: path): [
                    .target(name: aTarget.name, path: path),
                ],
                .target(name: cTarget.name, path: path): [
                    .target(name: bTarget.name, path: path),
                ],
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        let expectingTargets = [bTarget, cTarget]
        let pruningTargets = gotGraph.projects.values.flatMap(\.targets.values).sorted()
            .filter { $0.metadata.tags.contains("tuist:prunable") }

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertEqual(
            pruningTargets.map(\.name).sorted(),
            expectingTargets.map(\.name).sorted()
        )
    }

    func test_map_when_included_targets_is_target_with_dependencies_all_non_dependant_targets_are_pruned() throws {
        // Given
        let targetNames = ["foo", "bar", "baz"].shuffled()
        let aTarget = Target.test(name: targetNames[0])
        let bTarget = Target.test(name: targetNames[1])
        let cTarget = Target.test(name: targetNames[2])
        let subject = FocusTargetsGraphMappers(includedTargets: [.named(bTarget.name)])
        let path = try temporaryPath()
        let project = Project.test(path: path, targets: [aTarget, bTarget, cTarget])
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: bTarget.name, path: path): [
                    .target(name: aTarget.name, path: path),
                ],
                .target(name: cTarget.name, path: path): [
                    .target(name: bTarget.name, path: path),
                ],
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        let expectingTargets = [cTarget]
        let pruningTargets = gotGraph.projects.values.flatMap(\.targets.values).sorted()
            .filter { $0.metadata.tags.contains("tuist:prunable") }

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertEqual(
            pruningTargets.map(\.name).sorted(),
            expectingTargets.map(\.name).sorted()
        )
    }

    func test_map_when_included_targets_is_target_with_no_dependency_but_with_test_target_also_test_target_is_pruned() throws {
        // Given
        let targetNames = ["foo", "bar", "baz"].shuffled()
        let aTarget = Target.test(name: targetNames[0])
        let aTestTarget = Target.test(name: targetNames[0] + "Tests", product: .unitTests)
        let bTarget = Target.test(name: targetNames[1])
        let cTarget = Target.test(name: targetNames[2])
        let subject = FocusTargetsGraphMappers(includedTargets: [.named(aTarget.name)])
        let path = try temporaryPath()
        let project = Project.test(path: path, targets: [aTestTarget, aTarget, bTarget, cTarget])
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: aTestTarget.name, path: path): [
                    .target(name: aTarget.name, path: path),
                ],
                .target(name: bTarget.name, path: path): [
                    .target(name: aTarget.name, path: path),
                ],
                .target(name: cTarget.name, path: path): [
                    .target(name: bTarget.name, path: path),
                ],
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        let expectingTargets = [bTarget, cTarget, aTestTarget]
        let pruningTargets = gotGraph.projects.values.flatMap(\.targets.values).sorted()
            .filter { $0.metadata.tags.contains("tuist:prunable") }

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertEqual(
            pruningTargets.map(\.name).sorted(),
            expectingTargets.map(\.name).sorted()
        )
    }

    func test_map_when_included_targets_do_not_exist() throws {
        // Given
        let targetNames = ["foo", "bar", "baz"]
        let aTarget = Target.test(name: targetNames[0])
        let aTestTarget = Target.test(name: targetNames[0] + "Tests", product: .unitTests)
        let cTarget = Target.test(name: targetNames[2])
        let subject = FocusTargetsGraphMappers(includedTargets: [.named(aTarget.name), .named("bar")])
        let path = try temporaryPath()
        let project = Project.test(path: path, targets: [aTestTarget, aTarget, cTarget])
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: aTestTarget.name, path: path): [
                    .target(name: aTarget.name, path: path),
                ],
                .target(name: cTarget.name, path: path): [
                    .target(name: aTarget.name, path: path),
                ],
            ]
        )

        // When
        XCTAssertThrowsSpecific(
            try subject.map(graph: graph, environment: MapperEnvironment()),
            FocusTargetsGraphMappersError.targetsNotFound(["bar"])
        )
    }

    func test_map_when_included_products_prunes_non_test_dependency_targets() throws {
        // Given
        let framework = Target.test(name: "Framework")
        let frameworkTests = Target.test(name: "FrameworkTests", product: .unitTests)
        let exampleApp = Target.test(name: "FrameworkExample", product: .app)
        let subject = FocusTargetsGraphMappers(includedTargets: Set(), includedProducts: [.unitTests, .uiTests])
        let path = try temporaryPath()
        let project = Project.test(path: path, targets: [framework, frameworkTests, exampleApp])
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: frameworkTests.name, path: path): [
                    .target(name: framework.name, path: path),
                ],
                .target(name: exampleApp.name, path: path): [
                    .target(name: framework.name, path: path),
                ],
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try subject.map(graph: graph, environment: MapperEnvironment())
        let pruningTargets = gotGraph.projects.values.flatMap(\.targets.values).sorted()
            .filter { $0.metadata.tags.contains("tuist:prunable") }

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertEqual(pruningTargets.map(\.name), [exampleApp.name])
    }

    func test_map_when_included_products_does_not_prune_pre_action_build_settings_target() throws {
        // Given
        let appTarget = Target.test(name: "App", product: .app)
        let frameworkTests = Target.test(name: "FrameworkTests", product: .unitTests)
        let framework = Target.test(name: "Framework")
        let path = try temporaryPath()
        let project = Project.test(
            path: path,
            targets: [appTarget, framework, frameworkTests],
            schemes: [
                .test(
                    name: "FrameworkTests",
                    buildAction: .test(
                        targets: [TargetReference(projectPath: path, name: "FrameworkTests")],
                        preActions: [
                            ExecutionAction(
                                title: "Report build start",
                                scriptText: "echo $TARGET_BUILD_DIR",
                                target: TargetReference(projectPath: path, name: "App"),
                                shellPath: "/bin/sh"
                            ),
                        ]
                    ),
                    testAction: .test(
                        targets: [.test(target: TargetReference(projectPath: path, name: "FrameworkTests"))]
                    )
                ),
            ]
        )
        let subject = FocusTargetsGraphMappers(includedTargets: Set(), includedProducts: [.unitTests, .uiTests])
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: frameworkTests.name, path: path): [
                    .target(name: framework.name, path: path),
                ],
                .target(name: appTarget.name, path: path): [
                    .target(name: framework.name, path: path),
                ],
            ]
        )

        // When
        let (gotGraph, _, _) = try subject.map(graph: graph, environment: MapperEnvironment())
        let pruningTargets = gotGraph.projects.values.flatMap(\.targets.values).sorted()
            .filter { $0.metadata.tags.contains("tuist:prunable") }

        // Then — App should NOT be pruned because it's referenced as a pre-action build settings provider
        XCTAssertEmpty(pruningTargets.map(\.name))
    }

    func test_map_when_included_products_prunes_pre_action_target_from_fully_pruned_scheme() throws {
        // Given
        // A scheme whose only build target is an app (not a test) — the entire scheme will be pruned,
        // so its pre-action target should also be pruned
        let appTarget = Target.test(name: "App", product: .app)
        let helperTarget = Target.test(name: "Helper", product: .framework)
        let frameworkTests = Target.test(name: "FrameworkTests", product: .unitTests)
        let framework = Target.test(name: "Framework")
        let path = try temporaryPath()
        let project = Project.test(
            path: path,
            targets: [appTarget, helperTarget, framework, frameworkTests],
            schemes: [
                .test(
                    name: "AppScheme",
                    buildAction: .test(
                        targets: [TargetReference(projectPath: path, name: "App")],
                        preActions: [
                            ExecutionAction(
                                title: "Pre-action",
                                scriptText: "echo $TARGET_BUILD_DIR",
                                target: TargetReference(projectPath: path, name: "Helper"),
                                shellPath: "/bin/sh"
                            ),
                        ]
                    )
                ),
            ]
        )
        let subject = FocusTargetsGraphMappers(includedTargets: Set(), includedProducts: [.unitTests, .uiTests])
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: frameworkTests.name, path: path): [
                    .target(name: framework.name, path: path),
                ],
                .target(name: appTarget.name, path: path): [
                    .target(name: helperTarget.name, path: path),
                ],
            ]
        )

        // When
        let (gotGraph, _, _) = try subject.map(graph: graph, environment: MapperEnvironment())
        let pruningTargets = gotGraph.projects.values.flatMap(\.targets.values).sorted()
            .filter { $0.metadata.tags.contains("tuist:prunable") }

        // Then — App and Helper should both be pruned since the scheme has no surviving test targets
        XCTAssertEqual(
            pruningTargets.map(\.name).sorted(),
            ["App", "Helper"]
        )
    }

    func test_map_when_included_products_with_explicit_filters_uses_filters() throws {
        // Given
        let framework = Target.test(name: "Framework")
        let frameworkTests = Target.test(name: "FrameworkTests", product: .unitTests)
        let exampleApp = Target.test(name: "FrameworkExample", product: .app)
        let subject = FocusTargetsGraphMappers(
            includedTargets: [.named("FrameworkExample")],
            includedProducts: [.unitTests, .uiTests]
        )
        let path = try temporaryPath()
        let project = Project.test(path: path, targets: [framework, frameworkTests, exampleApp])
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: frameworkTests.name, path: path): [
                    .target(name: framework.name, path: path),
                ],
                .target(name: exampleApp.name, path: path): [
                    .target(name: framework.name, path: path),
                ],
            ]
        )

        // When
        let (gotGraph, _, _) = try subject.map(graph: graph, environment: MapperEnvironment())
        let pruningTargets = gotGraph.projects.values.flatMap(\.targets.values).sorted()
            .filter { $0.metadata.tags.contains("tuist:prunable") }

        // Then
        XCTAssertEqual(
            pruningTargets.map(\.name).sorted(),
            [frameworkTests.name]
        )
    }

    func test_map_when_included_targets_were_pruned_by_selective_testing_does_not_throw() throws {
        // Given
        let aTarget = Target.test(name: "App", product: .app)
        let aTests = Target.test(name: "AppTests", product: .unitTests)
        let libTests = Target.test(name: "LibTests", product: .unitTests)
        let subject = FocusTargetsGraphMappers(
            includedTargets: [.named("AppTests"), .named("LibTests")]
        )
        let path = try temporaryPath()
        // The initial graph (before selective testing) had LibTests
        let initialProject = Project.test(path: path, targets: [aTarget, aTests, libTests])
        let initialGraph = Graph.test(
            projects: [initialProject.path: initialProject],
            dependencies: [
                .target(name: aTests.name, path: path): [
                    .target(name: aTarget.name, path: path),
                ],
            ]
        )
        // After selective testing + tree shaking, LibTests was removed
        let project = Project.test(path: path, targets: [aTarget, aTests])
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: aTests.name, path: path): [
                    .target(name: aTarget.name, path: path),
                ],
            ]
        )
        var environment = MapperEnvironment()
        environment.initialGraph = initialGraph

        // When / Then — should not throw despite LibTests missing from the current graph
        let (_, gotSideEffects, _) = try subject.map(graph: graph, environment: environment)
        XCTAssertEmpty(gotSideEffects)
    }

    func test_map_when_some_included_targets_were_pruned_and_others_do_not_exist_throws() throws {
        // Given
        let aTarget = Target.test(name: "App", product: .app)
        let aTests = Target.test(name: "AppTests", product: .unitTests)
        let libTests = Target.test(name: "LibTests", product: .unitTests)
        let subject = FocusTargetsGraphMappers(
            includedTargets: [.named("AppTests"), .named("LibTests"), .named("NonExistent")]
        )
        let path = try temporaryPath()
        let initialProject = Project.test(path: path, targets: [aTarget, aTests, libTests])
        let initialGraph = Graph.test(
            projects: [initialProject.path: initialProject],
            dependencies: [
                .target(name: aTests.name, path: path): [
                    .target(name: aTarget.name, path: path),
                ],
            ]
        )
        let project = Project.test(path: path, targets: [aTarget, aTests])
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: aTests.name, path: path): [
                    .target(name: aTarget.name, path: path),
                ],
            ]
        )
        var environment = MapperEnvironment()
        environment.initialGraph = initialGraph

        // When / Then — LibTests is in initialGraph so it's fine, but NonExistent is truly missing
        XCTAssertThrowsSpecific(
            try subject.map(graph: graph, environment: environment),
            FocusTargetsGraphMappersError.targetsNotFound(["NonExistent"])
        )
    }

    func test_map_when_included_targets_is_unused_tag() throws {
        // Given
        let targetNames = ["foo"]
        let aTarget = Target.test(name: targetNames[0])
        let subject = FocusTargetsGraphMappers(includedTargets: [.tagged("tag")])
        let path = try temporaryPath()
        let project = Project.test(path: path, targets: [aTarget])
        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [:]
        )

        // When
        XCTAssertThrowsSpecific(
            try subject.map(graph: graph, environment: MapperEnvironment()),
            FocusTargetsGraphMappersError.noTargetsFound
        )
    }
}
