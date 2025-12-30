import XcodeGraph

public struct WorkspaceWithProjects: Equatable {
    public var workspace: Workspace
    public var projects: [Project]
    public init(workspace: Workspace, projects: [Project]) {
        self.workspace = workspace
        self.projects = projects
    }
}

#if DEBUG
    extension WorkspaceWithProjects {
        public static func test(
            workspace: Workspace = .test(),
            projects: [Project] = [.test()]
        ) -> WorkspaceWithProjects {
            WorkspaceWithProjects(
                workspace: workspace,
                projects: projects
            )
        }
    }
#endif

public protocol WorkspaceMapping {
    func map(workspace: WorkspaceWithProjects) async throws -> (WorkspaceWithProjects, [SideEffectDescriptor])
}

public final class SequentialWorkspaceMapper: WorkspaceMapping {
    let mappers: [WorkspaceMapping]

    public init(mappers: [WorkspaceMapping]) {
        self.mappers = mappers
    }

    public func map(workspace: WorkspaceWithProjects) async throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        var workspace = workspace
        var sideEffects: [SideEffectDescriptor] = []
        for mapper in mappers {
            let (mappedWorkspace, mappedSideEffects) = try await mapper.map(workspace: workspace)
            workspace = mappedWorkspace
            sideEffects.append(contentsOf: mappedSideEffects)
        }

        return (
            workspace,
            sideEffects
        )
    }
}

public final class ProjectWorkspaceMapper: WorkspaceMapping {
    private let mapper: ProjectMapping
    public init(mapper: ProjectMapping) {
        self.mapper = mapper
    }

    public func map(workspace: WorkspaceWithProjects) async throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        var projects: [Project] = []
        var sideEffects: [SideEffectDescriptor] = []
        for project in workspace.projects {
            let (mappedProject, mappedSideEffects) = try await mapper.map(project: project)
            projects.append(mappedProject)
            sideEffects.append(contentsOf: mappedSideEffects)
        }

        return (
            WorkspaceWithProjects(
                workspace: workspace.workspace,
                projects: projects
            ),
            sideEffects
        )
    }
}

#if DEBUG
    public final class MockWorkspaceMapper: WorkspaceMapping {
        public var mapStub: ((WorkspaceWithProjects) -> (WorkspaceWithProjects, [SideEffectDescriptor]))?
        public func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
            mapStub?(workspace) ?? (.test(), [])
        }
    }
#endif
