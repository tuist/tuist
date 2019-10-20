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
        
        guard graph.carthageDependencies.isEmpty == false else {
            return
        }
        
        guard CLI.arguments.carthage.projects == false else {
            return
        }
        
        guard CLI.arguments.carthage.build else {
            return
        }
        
        for carthage in graph.carthageDependencies {
            _ = try owner.generateProjectWorkspace(at: carthage.projectPath, workspaceFiles: [])
        }
        
        try carthageInteractor.build(graph: graph)
        
    }
    
}
