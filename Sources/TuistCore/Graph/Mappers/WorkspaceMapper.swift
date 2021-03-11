import Foundation
import TuistGraph

public struct WorkspaceWithProjects: Equatable {
    public var workspace: Workspace
    public var projects: [Project]
    public init(workspace: Workspace, projects: [Project]) {
        self.workspace = workspace
        self.projects = projects
    }
}

public protocol WorkspaceMapping {
    func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor])
}

public final class SequentialWorkspaceMapper: WorkspaceMapping {
    let mappers: [WorkspaceMapping]

    public init(mappers: [WorkspaceMapping]) {
        self.mappers = mappers
    }

    public func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        var results = (workspace: workspace, sideEffects: [SideEffectDescriptor]())
        results = try mappers.reduce(into: results) { results, mapper in
            let (updatedWorkspace, sideEffects) = try mapper.map(workspace: results.workspace)
            results.workspace = updatedWorkspace
            results.sideEffects.append(contentsOf: sideEffects)
        }
        return results
    }
}

public final class ProjectWorkspaceMapper: WorkspaceMapping {
    private let mapper: ProjectMapping
    public init(mapper: ProjectMapping) {
        self.mapper = mapper
    }

    public func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        var results = (projects: [Project](), sideEffects: [SideEffectDescriptor]())
        results = try workspace.projects.reduce(into: results) { results, project in
            let (updatedProject, sideEffects) = try mapper.map(project: project)
            results.projects.append(updatedProject)
            results.sideEffects.append(contentsOf: sideEffects)
        }
        let updatedWorkspace = WorkspaceWithProjects(
            workspace: workspace.workspace,
            projects: results.projects
        )
        return (updatedWorkspace, results.sideEffects)
    }
}
