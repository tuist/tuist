import Basic
import TuistCore

public struct CarthageHook: GenerateHook {
    
    public let owner: Generating
    
    public init(generator: Generating) {
        self.owner = generator
    }

    private let carthageInteractor: CarthageInteracting = CarthageInteractor()
    
    public func pre(path: AbsolutePath) throws {
        try carthageInteractor.checkout()
    }
    
    public func post(path: AbsolutePath) throws {
        
        guard let graph = Memoized.graph[path] else {
            return
        }
            
        if graph.carthageDependencies.isEmpty == false, CLI.arguments.carthage.projects == false {
            
            for carthage in graph.carthageDependencies {
                _ = try owner.generateProjectWorkspace(at: carthage.projectPath, workspaceFiles: [ ])
            }
            
            if CLI.arguments.carthage.build {
                try carthageInteractor.build(graph: graph)
            }
            
        }
    }
    
}
