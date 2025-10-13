import Foundation
import Path
import TuistCore
import XcodeGraph
import XCTest

@testable import TuistCacheEE
@testable import TuistTesting

final class GenerateCacheableSchemesWorkspaceMapperTests: TuistUnitTestCase {
    func test_generate_binary_and_bundles_schemes() throws {
        // Given
        let targetA = Target.test(name: "A", destinations: [.iPhone], product: .framework)
        let targetB = Target.test(name: "B", destinations: [.iPhone], product: .app)
        let targetC = Target.test(name: "C", destinations: [.mac], product: .framework)
        let bundle = Target.test(name: "Bundle", destinations: [.appleTv], product: .bundle)
        let macro = Target.test(name: "Macro", destinations: [.appleTv], product: .macro)

        let includedTargets = [targetA, targetC, bundle, macro].map(\.name)
        let subject = GenerateCacheableSchemesWorkspaceMapper(targets: [
            .iOS: Set([.named(targetA.name)]),
            .macOS: Set([.named(targetC.name)]),
            .tvOS: Set([.named(bundle.name), .named(macro.name)]),
        ])
        let projectA = Project.test(name: "A", targets: [targetA, bundle, macro])
        let projectB = Project.test(name: "B", targets: [targetB, targetC])
        let workspace = Workspace.test()
        let workspaceWithProjects = WorkspaceWithProjects(
            workspace: workspace, projects: [projectA, projectB]
        )

        // When
        let (updatedWorkspace, sideEffects) = try subject.map(workspace: workspaceWithProjects)

        // Then
        XCTAssertEqual(
            updatedWorkspace.workspace.schemes.map(\.name),
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
            updatedWorkspace.workspace.schemes.first(where: { $0.name == "Binaries-Cache-iOS" })?
                .buildAction?.targets
                .map(\.name),
            [
                "A",
            ]
        )
        XCTAssertEqual(
            updatedWorkspace.workspace.schemes.first(where: { $0.name == "Binaries-Cache-macOS" })?
                .buildAction?.targets
                .map(\.name),
            [
                "C",
            ]
        )
        XCTAssertEqual(
            updatedWorkspace.workspace.schemes.first(where: { $0.name == "Bundles-Cache-tvOS" })?
                .buildAction?.targets
                .map(\.name),
            [
                "Bundle",
            ]
        )

        XCTAssertEqual(
            updatedWorkspace.workspace.schemes.first(where: { $0.name == "Macros-Cache-tvOS" })?
                .buildAction?.targets.map(\.name),
            [
                "Macro",
            ]
        )

        XCTAssertEqual(
            updatedWorkspace.workspace.schemes.flatMap { $0.buildAction?.targets ?? [] }.map(
                \.name
            ), includedTargets
        )
        XCTAssertTrue(sideEffects.isEmpty)
    }
}
