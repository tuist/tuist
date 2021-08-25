import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import XCTest
@testable import TuistKit
@testable import TuistSupportTesting

final class GenerateCacheableSchemesWorkspaceMapperTests: XCTestCase {
    func test_generate_binary_and_bundles_schemes() throws {
        // Given
        let targetA = Target.test(name: "A", platform: .iOS, product: .framework)
        let targetB = Target.test(name: "B", platform: .iOS)
        let targetC = Target.test(name: "C", platform: .macOS, product: .framework)
        let bundle = Target.test(name: "Bundle", platform: .tvOS, product: .bundle)

        let includedTargets = [targetA, targetC, bundle]
        let subject = GenerateCacheableSchemesWorkspaceMapper(includedTargets: includedTargets)
        let projectA = Project.test(name: "A", targets: [targetA, bundle])
        let projectB = Project.test(name: "B", targets: [targetB, targetC])
        let workspace = Workspace.test()
        let workspaceWithProjects = WorkspaceWithProjects(workspace: workspace, projects: [projectA, projectB])

        // When
        let (updatedWorkspace, sideEffects) = try subject.map(workspace: workspaceWithProjects)

        // Then
        XCTAssertEqual(updatedWorkspace.workspace.schemes.map(\.name), [
            "ProjectCache-Bundles-iOS",
            "ProjectCache-Binaries-iOS",
            "ProjectCache-Bundles-macOS",
            "ProjectCache-Binaries-macOS",
            "ProjectCache-Bundles-tvOS",
            "ProjectCache-Binaries-tvOS",
            "ProjectCache-Bundles-watchOS",
            "ProjectCache-Binaries-watchOS",
        ])
        XCTAssertEqual(updatedWorkspace.workspace.schemes[1].buildAction?.targets.map(\.name), [
            "A",
        ])
        XCTAssertEqual(updatedWorkspace.workspace.schemes[3].buildAction?.targets.map(\.name), [
            "C",
        ])
        XCTAssertEqual(updatedWorkspace.workspace.schemes[4].buildAction?.targets.map(\.name), [
            "Bundle",
        ])
        XCTAssertEqual(updatedWorkspace.workspace.schemes.flatMap { $0.buildAction?.targets ?? [] }.map(\.name), includedTargets.map(\.name))
        XCTAssertTrue(sideEffects.isEmpty)
    }
}
