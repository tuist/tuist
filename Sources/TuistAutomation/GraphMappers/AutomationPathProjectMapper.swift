import TuistCore
import TuistSupport

/// Updates path of project to point to where automation project should be generated
public final class AutomationPathProjectMapper: ProjectMapping {
    private let contentHasher: ContentHashing
    
    public init(
        contentHasher: ContentHashing = ContentHasher()
    ) {
        self.contentHasher = contentHasher
    }
    
    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        var project = project
        let pathHash = try contentHasher.hash(project.path.pathString)
        let projectsDirectory = Environment.shared.projectsCacheDirectory
            .appending(component: project.name + "-" + pathHash)
        let xcodeProjBasename = project.xcodeProjPath.basename
        project.xcodeProjPath = projectsDirectory.appending(component: xcodeProjBasename)
        return (
            project,
            [
                .directory(
                    DirectoryDescriptor(
                        path: projectsDirectory,
                        state: .present
                    )
                ),
            ]
        )
    }
}

public final class AutomationPathGraphMapper: GraphMapping {
    private let contentHasher: ContentHashing
    
    public init(
        contentHasher: ContentHashing = ContentHasher()
    ) {
        self.contentHasher = contentHasher
    }
    
    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        let pathHash = try contentHasher.hash(project.path.pathString)
    }
}
