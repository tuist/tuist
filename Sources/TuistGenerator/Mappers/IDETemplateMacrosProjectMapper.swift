import Foundation
import TSCBasic
import TuistCore
import TuistGraph

public final class IDETemplateMacrosProjectMapper: ProjectMapping {
    public init() {
        
    }
    
    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        guard let ideTemplateMacros = project.ideTemplateMacros else { return (project, []) }
        
        let encoder = PropertyListEncoder()
        let data = try encoder.encode(ideTemplateMacros)

        return (project, [
            .file(FileDescriptor(
                path: project.xcodeProjPath.appending(RelativePath("xcshareddata/IDETemplateMacros.plist")),
                contents: data
            )),
        ])
    }
}
