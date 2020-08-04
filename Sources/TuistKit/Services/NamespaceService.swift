import TSCBasic
import TuistSupport
import TuistGenerator

struct NamespaceService {
    let projectGenerator: ProjectGenerating
    let sideEffectDescriptorExecutor: SideEffectDescriptorExecuting
    
    init(
        projectGenerator: ProjectGenerating = ProjectGenerator(),
        sideEffectDescriptorExecutor: SideEffectDescriptorExecuting = SideEffectDescriptorExecutor()
    ) {
        self.projectGenerator = projectGenerator
        self.sideEffectDescriptorExecutor = sideEffectDescriptorExecutor
    }
    
    func run(
        path: String?
    ) throws {
        let path = self.path(path)
        let graph = try projectGenerator.load(path: path)
        let resourcesNamespaceProjectMapper = ResourcesNamespaceProjectMapper()
        let sideEffects = try graph.projects
            .map(resourcesNamespaceProjectMapper.map)
            .map(\.1)
            .flatMap { $0 }
        
        try sideEffectDescriptorExecutor.execute(sideEffects: sideEffects)
    }
    
    // MARK: - Helpers

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
