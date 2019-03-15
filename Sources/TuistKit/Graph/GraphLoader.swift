import Basic
import Foundation
import TuistCore

protocol GraphLoading: AnyObject {
    func loadProject(path: AbsolutePath) throws -> (WorkspaceStructure, Graph)
    func loadWorkspace(path: AbsolutePath) throws -> (WorkspaceStructure, Graph)
}

class GraphLoader: GraphLoading {
    // MARK: - Attributes

    let linter: GraphLinting
    let printer: Printing
    let fileHandler: FileHandling
    let modelLoader: GeneratorModelLoading

    // MARK: - Init

    init(linter: GraphLinting = GraphLinter(),
         printer: Printing = Printer(),
         fileHandler: FileHandling = FileHandler(),
         modelLoader: GeneratorModelLoading) {
        self.linter = linter
        self.printer = printer
        self.fileHandler = fileHandler
        self.modelLoader = modelLoader
    }

    func loadProject(path: AbsolutePath) throws -> (WorkspaceStructure, Graph) {
        let cache = GraphLoaderCache()
        let circularDetector = GraphCircularDetector()
        
        let project = try Project.at(path, cache: cache, circularDetector: circularDetector, modelLoader: modelLoader)
        let entryNodes: [GraphNode] = try project.targets.map(\.name).map { targetName in
            try TargetNode.read(name: targetName, path: path, cache: cache, circularDetector: circularDetector, modelLoader: modelLoader)
        }
        let graph = Graph(name: project.name,
                          entryPath: path,
                          cache: cache,
                          entryNodes: entryNodes)
                
        try lint(graph: graph)
        
        let workspaceStructure = WorkspaceStructure(name: "Workspace", contents: graph.projects.keys.map(WorkspaceStructure.Element.project))
        
        return (workspaceStructure, graph)
    }

    func loadWorkspace(path: AbsolutePath) throws -> (WorkspaceStructure, Graph) {
        
        let cache = GraphLoaderCache()
        let circularDetector = GraphCircularDetector()
        let workspaceDescription = try modelLoader.loadWorkspace(at: path)

        let projects = try workspaceDescription.projects.map {
            return ($0, try Project.at($0, cache: cache, circularDetector: circularDetector, modelLoader: modelLoader))
        }

        let entryNodes = try projects.flatMap { projectPath, project -> [TargetNode] in
            try project.targets.map(\.name).map { targetName in
                try TargetNode.read(name: targetName, path: projectPath, cache: cache, circularDetector: circularDetector, modelLoader: modelLoader)
            }
        }
        let graph = Graph(name: workspaceDescription.name,
                          entryPath: path,
                          cache: cache,
                          entryNodes: entryNodes)
        
        try lint(graph: graph)
        
        workspaceDescription.projects = Array(graph.projects.keys)

        return (try WorkspaceStructureFactory(path: path, workspace: workspaceDescription).makeWorkspaceStructure(), graph)
    }

    private func lint(graph: Graph) throws {
        try linter.lint(graph: graph).printAndThrowIfNeeded(printer: printer)
    }
 
}
