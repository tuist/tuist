import Foundation
import TSCBasic
import TuistCoreTesting
import XCTest

@testable import TuistCore

final class SequentialWorkspaceMapperTests: XCTestCase {
    func test_map_workspace() throws {
        // Given
        let mapper1 = WorkspaceMapper { workspace, _ in
            (Workspace.test(name: "Update1_\(workspace.name)"), [])
        }
        let mapper2 = WorkspaceMapper { workspace, _ in
            (Workspace.test(name: "Update2_\(workspace.name)"), [])
        }
        let subject = SequentialWorkspaceMapper(mappers: [mapper1, mapper2])
        let workspace = Workspace.test(name: "Workspace")

        // When
        let (updatedWorkspace, sideEffects) = try subject.map(workspace: workspace, graph: Graph.test())

        // Then
        XCTAssertEqual(updatedWorkspace.name, "Update2_Update1_Workspace")
        XCTAssertTrue(sideEffects.isEmpty)
    }

    func test_map_sideEffects() throws {
        // Given
        let mapper1 = WorkspaceMapper { workspace, _ in
            (Workspace.test(name: "Update1_\(workspace.name)"), [
                .command(.init(command: ["command 1"])),
            ])
        }
        let mapper2 = WorkspaceMapper { workspace, _ in
            (Workspace.test(name: "Update2_\(workspace.name)"), [
                .command(.init(command: ["command 2"])),
            ])
        }
        let subject = SequentialWorkspaceMapper(mappers: [mapper1, mapper2])
        let workspace = Workspace.test(name: "Workspace")

        // When
        let (_, sideEffects) = try subject.map(workspace: workspace, graph: Graph.test())

        // Then
        XCTAssertEqual(sideEffects, [
            .command(.init(command: ["command 1"])),
            .command(.init(command: ["command 2"])),
        ])
    }

    // MARK: - Helpers

    private class WorkspaceMapper: WorkspaceMapping {
        let mapper: (Workspace, Graph) -> (Workspace, [SideEffectDescriptor])
        init(mapper: @escaping (Workspace, Graph) -> (Workspace, [SideEffectDescriptor])) {
            self.mapper = mapper
        }

        func map(workspace: Workspace, graph: Graph) throws -> (Workspace, [SideEffectDescriptor]) {
            return mapper(workspace, graph)
        }
    }
}
