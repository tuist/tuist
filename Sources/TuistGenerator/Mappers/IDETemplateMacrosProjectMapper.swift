import Foundation
import TSCBasic
import TuistCore
import TuistGraph

public final class IDETemplateMacrosProjectMapper: ProjectMapping {
    public let config: Config
    
    public init(config: Config) {
        self.config = config
    }
    
    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        guard let templateMacros = templateMacros() else { return (project, []) }
        
        let encoder = PropertyListEncoder()
        let data = try encoder.encode(templateMacros)
        
        return (project, [
            .file(FileDescriptor(
                    path: project.xcodeProjPath.appending(RelativePath("xcshareddata/IDETemplateMacros.plist")),
                    contents: data)),
        ])
    }
    
    private func templateMacros() -> IDETemplateMacros? {
        config.generationOptions.compactMap { item -> IDETemplateMacros? in
            switch item {
            case let .templateMacros(templateMacros):
                return templateMacros
            default:
                return nil
            }
        }.first
    }
}
