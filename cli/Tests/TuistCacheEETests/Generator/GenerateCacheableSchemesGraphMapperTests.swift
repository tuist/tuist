import Foundation
import Path
import TuistCore
import XcodeGraph
import XCTest

@testable import TuistCacheEE
@testable import TuistTesting

final class GenerateCacheableSchemesGraphMapperTests: TuistUnitTestCase {
    func test_generate_binary_and_bundles_schemes() async throws {
        // Given
        let directory = try temporaryPath()

        let targetA = Target.test(name: "A", destinations: [.iPhone], product: .framework)
        let targetB = Target.test(name: "B", destinations: [.iPhone], product: .app)
        let targetC = Target.test(name: "C", destinations: [.mac], product: .framework)
        let bundle = Target.test(name: "Bundle", destinations: [.appleTv], product: .bundle)
        let macro = Target.test(name: "Macro", destinations: [.appleTv], product: .macro)

        let includedTargets = [targetA, targetC, bundle, macro].map(\.name)
        let subject = GenerateCacheableSchemesGraphMapper(targets: [
            .iOS: Set([.named(targetA.name)]),
            .macOS: Set([.named(targetC.name)]),
            .tvOS: Set([.named(bundle.name), .named(macro.name)]),
        ])
        let projectAPath = directory.appending(component: "ProjectA")
        let projectBPath = directory.appending(component: "ProjectB")
        let projectA = Project.test(path: projectAPath, name: "A", targets: [targetA, bundle, macro])
        let projectB = Project.test(path: projectBPath, name: "B", targets: [targetB, targetC])

        let graph = Graph.test(
            workspace: Workspace.test(projects: [projectAPath, projectBPath]),
            projects: [
                projectAPath: projectA,
                projectBPath: projectB,
            ]
        )

        // When
        let (updatedGraph, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEqual(
            updatedGraph.workspace.schemes.map(\.name),
            [
                "Binaries-Cache-iOS",
                "Bundles-Cache-iOS",
                "Macros-Cache-iOS",
                "Binaries-Cache-macOS",
                "Bundles-Cache-macOS",
                "Macros-Cache-macOS",
                "Binaries-Cache-tvOS",
                "Bundles-Cache-tvOS",
                "Macros-Cache-tvOS",
                "Binaries-Cache-watchOS",
                "Bundles-Cache-watchOS",
                "Macros-Cache-watchOS",
                "Binaries-Cache-visionOS",
                "Bundles-Cache-visionOS",
                "Macros-Cache-visionOS",
            ]
        )

        XCTAssertEqual(
            updatedGraph.workspace.schemes.first(where: { $0.name == "Binaries-Cache-iOS" })?
                .buildAction?.targets
                .map(\.name),
            [
                "A",
            ]
        )
        XCTAssertEqual(
            updatedGraph.workspace.schemes.first(where: { $0.name == "Binaries-Cache-macOS" })?
                .buildAction?.targets
                .map(\.name),
            [
                "C",
            ]
        )
        XCTAssertEqual(
            updatedGraph.workspace.schemes.first(where: { $0.name == "Bundles-Cache-tvOS" })?
                .buildAction?.targets
                .map(\.name),
            [
                "Bundle",
            ]
        )

        XCTAssertEqual(
            updatedGraph.workspace.schemes.first(where: { $0.name == "Macros-Cache-tvOS" })?
                .buildAction?.targets.map(\.name),
            [
                "Macro",
            ]
        )

        XCTAssertEqual(
            updatedGraph.workspace.schemes.flatMap { $0.buildAction?.targets ?? [] }.map(
                \.name
            ), includedTargets
        )
        XCTAssertTrue(sideEffects.isEmpty)
    }

    func test_generate_catalyst_scheme_for_targets_that_support_catalyst() async throws {
        // Given
        let directory = try temporaryPath()

        let targetWithCatalyst = Target.test(name: "WithCatalyst", destinations: [.iPhone, .macCatalyst], product: .framework)
        let targetWithoutCatalyst = Target.test(name: "WithoutCatalyst", destinations: [.iPhone], product: .framework)

        let subject = GenerateCacheableSchemesGraphMapper(targets: [
            .iOS: Set([.named(targetWithCatalyst.name), .named(targetWithoutCatalyst.name)]),
        ])
        let projectPath = directory.appending(component: "App")
        let project = Project.test(path: projectPath, name: "App", targets: [targetWithCatalyst, targetWithoutCatalyst])

        let graph = Graph.test(
            workspace: Workspace.test(projects: [projectPath]),
            projects: [projectPath: project]
        )

        // When
        let (updatedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertTrue(updatedGraph.workspace.schemes.map(\.name).contains("Binaries-Cache-Catalyst"))

        XCTAssertEqual(
            updatedGraph.workspace.schemes.first(where: { $0.name == "Binaries-Cache-Catalyst" })?
                .buildAction?.targets
                .map(\.name),
            [
                "WithCatalyst",
            ]
        )

        XCTAssertEqual(
            updatedGraph.workspace.schemes.first(where: { $0.name == "Binaries-Cache-iOS" })?
                .buildAction?.targets
                .map(\.name),
            [
                "WithCatalyst",
                "WithoutCatalyst",
            ]
        )
    }

    func test_does_not_generate_catalyst_scheme_when_no_targets_support_catalyst() async throws {
        // Given
        let directory = try temporaryPath()

        let targetA = Target.test(name: "A", destinations: [.iPhone], product: .framework)
        let targetB = Target.test(name: "B", destinations: [.iPhone], product: .framework)

        let subject = GenerateCacheableSchemesGraphMapper(targets: [
            .iOS: Set([.named(targetA.name), .named(targetB.name)]),
        ])
        let projectPath = directory.appending(component: "App")
        let project = Project.test(path: projectPath, name: "App", targets: [targetA, targetB])

        let graph = Graph.test(
            workspace: Workspace.test(projects: [projectPath]),
            projects: [projectPath: project]
        )

        // When
        let (updatedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertFalse(updatedGraph.workspace.schemes.map(\.name).contains("Binaries-Cache-Catalyst"))
    }
}
