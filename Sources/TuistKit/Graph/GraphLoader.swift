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
        
        let dependencies = graph.projects.keys.filter{ $0 != path }.map(WorkspaceStructure.Element.project)
        
        let workspaceStructure = WorkspaceStructure(name: "Workspace", contents: [
            .project(path: path),
            .group(name: "Dependencies", contents: dependencies)
        ])
        
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

        return (try WorkspaceStructureFactory(path: path, workspace: workspaceDescription).makeWorkspaceStructure(), graph)
    }

    private func lint(graph: Graph) throws {
        try linter.lint(graph: graph).printAndThrowIfNeeded(printer: printer)
    }
 
}

struct WorkspaceStructure {
    
    indirect enum Element: Equatable {
        case file(path: AbsolutePath)
        case folderReference(path: AbsolutePath)
        case group(name: String, contents: [Element])
        case project(path: AbsolutePath)
    }

    let name: String
    let contents: [Element]
    
}

struct DirectoryStructure {
    
    typealias Graph = [Node]
    
    let path: AbsolutePath
    let fileHandler: FileHandling
    
    let projects: [AbsolutePath]
    let files: [AbsolutePath]

    init(path: AbsolutePath, fileHandler: FileHandling = FileHandler(), projects: [AbsolutePath], files: [AbsolutePath]) {
        self.path = path
        self.fileHandler = fileHandler
        self.projects = projects
        self.files = files
    }

    indirect enum Node {
        case file(AbsolutePath)
        case directory(AbsolutePath, Graph)
    }
    
    internal func buildGraph() throws -> Graph {
        return try buildGraph(path: path)
    }
    
    private func buildGraph(path: AbsolutePath, test: () -> Bool = { true }) throws -> Graph {
        
        return try fileHandler.ls(path).compactMap { path in
            
            let isProjectDirectory = projects.contains(where: { $0.contains(path) })
            let isManifestFile = path.basename == Manifest.project.fileName
            let isAdditionalFile = files.matches(path: path)

            guard isProjectDirectory || isManifestFile || isAdditionalFile else {
                return nil
            }
            
            if fileHandler.isFolder(path) {
                return .directory(path, try buildGraph(path: path))
            } else {
                return .file(path)
            }
            
        }
        
    }
    
}

struct WorkspaceStructureFactory {
    
    let path: AbsolutePath
    let workspace: Workspace
    
    private func directoryGraphToWorkspaceStructureElement(content: DirectoryStructure.Node) -> WorkspaceStructure.Element? {
        
        switch content {
        case .file(let file) where file.basename == Manifest.project.fileName:
            return nil
        case .file(let file):
            return .file(path: file)
        case .directory(let path, _) where path.suffix == ".playground":
            return .file(path: path)
        case .directory(let path, let contents) where contents.contains(fileName: Manifest.project.fileName):
            return .project(path: path)
        case .directory(let path, let contents) where contents.containsInGraph(fileName: Manifest.project.fileName):
            return .group(name: path.basename, contents: contents.compactMap(directoryGraphToWorkspaceStructureElement))
        case .directory(let path, _):
            return .folderReference(path: path)
        }
        
    }
    
    func makeWorkspaceStructure() throws -> WorkspaceStructure {
        let graph = try DirectoryStructure(path: path, projects: workspace.projects, files: workspace.additionalFiles).buildGraph()
        return WorkspaceStructure(name: workspace.name, contents: graph.compactMap(directoryGraphToWorkspaceStructureElement))
    }
    
}

extension Sequence where Element == AbsolutePath {
    
    func contains(fileName: String) -> Bool {
        return contains(where: { $0.basename == fileName })
    }
    
    func matches(path: AbsolutePath) -> Bool {
        return contains(where: { $0.contains(path) || path.contains($0) })
    }
    
}

extension Sequence where Element == DirectoryStructure.Node {
    
    func files() -> [AbsolutePath] {
        return compactMap{ content in
            switch content {
            case .file(let path): return path
            case .directory: return nil
            }
        }
    }
    
    func contains(fileName: String) -> Bool {
        return files().contains(fileName: fileName)
    }
    
    func containsInGraph(fileName: String) -> Bool {
        
        return first{ node in
            
            switch node {
            case .file(let path) where path.basename == fileName:
                return true
            case .directory(_, let graph):
                return graph.containsInGraph(fileName: fileName)
            case _:
                return false
            }
            
        } != nil
        
    }
    
}
