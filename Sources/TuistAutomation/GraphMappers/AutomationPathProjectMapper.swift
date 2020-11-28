import TuistCore
import TuistSupport
import TSCBasic

/// Updates path of project to point to where automation project should be generated
public final class AutomationPathProjectMapper: ProjectMapping {
    private let temporaryDirectory: AbsolutePath
    
    public init(
        temporaryDirectory: AbsolutePath
    ) {
        self.temporaryDirectory = temporaryDirectory
    }
    
    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        var project = project
        let xcodeProjBasename = project.xcodeProjPath.basename
        project.sourceRootPath = temporaryDirectory
        project.xcodeProjPath = temporaryDirectory.appending(component: xcodeProjBasename)
        return (
            project,
            [
                .directory(
                    DirectoryDescriptor(
                        path: temporaryDirectory,
                        state: .present
                    )
                ),
            ]
        )
    }
}
