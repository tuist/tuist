import TSCBasic
import TuistCore
import TuistSupport
import TuistGraph

/// Updates path of project to point to where automation project should be generated
public final class AutomationPathProjectMapper: ProjectMapping {
    private let xcodeProjDirectory: AbsolutePath

    public init(
        xcodeProjDirectory: AbsolutePath
    ) {
        self.xcodeProjDirectory = xcodeProjDirectory
    }

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        var project = project
        let xcodeProjBasename = project.xcodeProjPath.basename
        project.sourceRootPath = xcodeProjDirectory
        project.xcodeProjPath = xcodeProjDirectory.appending(component: xcodeProjBasename)
        return (
            project,
            [
                .directory(
                    DirectoryDescriptor(
                        path: xcodeProjDirectory,
                        state: .present
                    )
                ),
            ]
        )
    }
}
