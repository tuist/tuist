import TSCBasic
import TuistSupport
import TuistGenerator
import TuistCore

struct NamespaceService {
    private let projectGenerator: ProjectGenerating
    private let sideEffectDescriptorExecutor: SideEffectDescriptorExecuting
    private let resourcesNamespaceProjectMapper: ProjectMapping
    
    init(
        projectGenerator: ProjectGenerating = ProjectGenerator(),
        sideEffectDescriptorExecutor: SideEffectDescriptorExecuting = SideEffectDescriptorExecutor(),
        resourcesNamespaceProjectMapper: ProjectMapping = ResourcesNamespaceProjectMapper()
    ) {
        self.projectGenerator = projectGenerator
        self.sideEffectDescriptorExecutor = sideEffectDescriptorExecutor
        self.resourcesNamespaceProjectMapper = resourcesNamespaceProjectMapper
    }
    
    func run(
        path: String?
    ) throws {
        let path = self.path(path)
        let graph = try projectGenerator.load(path: path)
        let sideEffects = try graph.projects
            .map(resourcesNamespaceProjectMapper.map)
            .map(\.1)
            .flatMap { $0 }
        
        try sideEffectDescriptorExecutor.execute(sideEffects: sideEffects)
        
        logger.notice("Namespace generated.", metadata: .success)
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
