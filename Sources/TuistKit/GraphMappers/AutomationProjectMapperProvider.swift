import Foundation
import TuistCore
import TuistSupport

final class AutomationWorkspaceMapperProvider: WorkspaceMapperProviding {
    private let workspaceMapperProvider: WorkspaceMapperProviding
    
    init(
        workspaceMapperProvider: WorkspaceMapperProviding = WorkspaceMapperProvider()
    ) {
        self.workspaceMapperProvider = workspaceMapperProvider
    }
    
    func mapper(config: Config) -> WorkspaceMapping {
        var mappers: [WorkspaceMapping] = []
        mappers.append(AutomationPathWorkspaceMapper())
        mappers.append(workspaceMapperProvider.mapper(config: config))
        return SequentialWorkspaceMapper(mappers: mappers)
    }
}

final class AutomationPathWorkspaceMapper: WorkspaceMapping {
    private let contentHasher: ContentHashing
    
    init(
        contentHasher: ContentHashing = ContentHasher()
    ) {
        self.contentHasher = contentHasher
    }
    
    func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        var workspace = workspace
        let pathHash = try contentHasher.hash(workspace.workspace.path.pathString)
        let projectsDirectory = Environment.shared.projectsCacheDirectory
            .appending(component: workspace.workspace.name + "-" + pathHash)
        try FileHandler.shared.createFolder(projectsDirectory)
        workspace.workspace.path = projectsDirectory
        return (workspace, [])
    }
}

final class AutomationProjectMapperProvider: ProjectMapperProviding {
    private let projectMapperProvider: ProjectMapperProviding
    private let contentHasher: ContentHashing
    
    init(
        projectMapperProvider: ProjectMapperProviding = ProjectMapperProvider(),
        contentHasher: ContentHashing = ContentHasher()
    ) {
        self.projectMapperProvider = projectMapperProvider
        self.contentHasher = contentHasher
    }

    func mapper(config: Config) -> ProjectMapping {
        var mappers: [ProjectMapping] = []
        mappers.append(AutomationPathProjectMapper())
        mappers.append(projectMapperProvider.mapper(config: config))
        
        return SequentialProjectMapper(mappers: mappers)
    }
}

final class AutomationPathProjectMapper: ProjectMapping {
    private let contentHasher: ContentHashing
    
    init(
        contentHasher: ContentHashing = ContentHasher()
    ) {
        self.contentHasher = contentHasher
    }
    
    func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        var project = project
        let pathHash = try contentHasher.hash(project.path.pathString)
        let projectsDirectory = Environment.shared.projectsCacheDirectory
            .appending(component: project.name + "-" + pathHash)
        try FileHandler.shared.createFolder(projectsDirectory)
        let xcodeProjBasename = project.xcodeProjPath.basename
        project.xcodeProjPath = projectsDirectory.appending(component: xcodeProjBasename)
        return (project, [])
    }
}
