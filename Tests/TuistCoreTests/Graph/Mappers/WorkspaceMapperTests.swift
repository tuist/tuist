import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import XCTest
@testable import TuistSupportTesting

final class ProjectWorkspaceMapperTests: XCTestCase {
    func test_map_workspace() throws {
        // Given
        let projectMapper = ProjectMapper {
            var updated = $0
            updated.name = "Updated_\($0.name)"
            return (updated, [])
        }
        let subject = ProjectWorkspaceMapper(mapper: projectMapper)
        let projectA = Project.test(name: "A")
        let projectB = Project.test(name: "B")
        let workspace = Workspace.test()
        let workspaceWithProjects = WorkspaceWithProjects(workspace: workspace, projects: [projectA, projectB])

        // When
        let (updatedWorkspace, sideEffects) = try subject.map(workspace: workspaceWithProjects)

        // Then
        XCTAssertEqual(updatedWorkspace.projects.map(\.name), [
            "Updated_A",
            "Updated_B",
        ])
        XCTAssertTrue(sideEffects.isEmpty)
    }

    func test_map_sideEffects() throws {
        // Given
        let projectMapper = ProjectMapper {
            var updated = $0
            updated.name = "Updated_\($0.name)"
            return (updated, [
                .file(.init(path: try! AbsolutePath(validating: "/Projects/\($0.name).swift"))),
            ])
        }
        let subject = ProjectWorkspaceMapper(mapper: projectMapper)
        let projectA = Project.test(name: "A")
        let projectB = Project.test(name: "B")
        let workspace = Workspace.test()
        let workspaceWithProjects = WorkspaceWithProjects(workspace: workspace, projects: [projectA, projectB])

        // When
        let (_, sideEffects) = try subject.map(workspace: workspaceWithProjects)

        // Then
        XCTAssertEqual(sideEffects, [
            .file(.init(path: try AbsolutePath(validating: "/Projects/A.swift"))),
            .file(.init(path: try AbsolutePath(validating: "/Projects/B.swift"))),
        ])
    }

    // MARK: - Helpers

    private class ProjectMapper: ProjectMapping {
        let mapper: (Project) -> (Project, [SideEffectDescriptor])
        init(mapper: @escaping (Project) -> (Project, [SideEffectDescriptor])) {
            self.mapper = mapper
        }

        func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
            return mapper(project)
        }
    }
}

final class SequentialWorkspaceMapperTests: XCTestCase {
    func test_map_workspace() throws {
        // Given
        let mapper1 = WorkspaceMapper {
            var updated = $0
            updated.workspace.name = "Updated1_\($0.workspace.name)"
            updated.projects.append(Project.test(name: "ProjectA"))
            return (updated, [])
        }
        let mapper2 = WorkspaceMapper {
            var updated = $0
            updated.workspace.name = "Updated2_\($0.workspace.name)"
            updated.projects.append(Project.test(name: "ProjectB"))
            return (updated, [])
        }
        let subject = SequentialWorkspaceMapper(mappers: [mapper1, mapper2])
        let workspace = Workspace.test(name: "Workspace")
        let workspaceWithProjects = WorkspaceWithProjects(workspace: workspace, projects: [])

        // When
        let (updatedWorkspace, sideEffects) = try subject.map(workspace: workspaceWithProjects)

        // Then
        XCTAssertEqual(updatedWorkspace.workspace.name, "Updated2_Updated1_Workspace")
        XCTAssertEqual(updatedWorkspace.projects.map(\.name), [
            "ProjectA",
            "ProjectB",
        ])
        XCTAssertTrue(sideEffects.isEmpty)
    }

    func test_map_sideEffects() throws {
        // Given
        let mapper1 = WorkspaceMapper {
            ($0, [
                .command(.init(command: ["command 1"])),
            ])
        }
        let mapper2 = WorkspaceMapper {
            ($0, [
                .command(.init(command: ["command 2"])),
            ])
        }
        let subject = SequentialWorkspaceMapper(mappers: [mapper1, mapper2])
        let workspace = Workspace.test(name: "Workspace")
        let workspaceWithProjects = WorkspaceWithProjects(workspace: workspace, projects: [])

        // When
        let (_, sideEffects) = try subject.map(workspace: workspaceWithProjects)

        // Then
        XCTAssertEqual(sideEffects, [
            .command(.init(command: ["command 1"])),
            .command(.init(command: ["command 2"])),
        ])
    }

    // MARK: - Helpers

    private class WorkspaceMapper: WorkspaceMapping {
        let mapper: (WorkspaceWithProjects) -> (WorkspaceWithProjects, [SideEffectDescriptor])
        init(mapper: @escaping (WorkspaceWithProjects) -> (WorkspaceWithProjects, [SideEffectDescriptor])) {
            self.mapper = mapper
        }

        func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
            return mapper(workspace)
        }
    }
}
