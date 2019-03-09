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
        
        let workspace = try WorkspaceStructureFactory(path: path, workspace: try modelLoader.loadWorkspace(at: path)).makeWorkspaceStructure()
        
        let project = try Project.at(path, cache: cache, circularDetector: circularDetector, modelLoader: modelLoader)
        let entryNodes: [GraphNode] = try project.targets.map({ $0.name }).map { targetName in
            try TargetNode.read(name: targetName, path: path, cache: cache, circularDetector: circularDetector, modelLoader: modelLoader)
        }
        let graph = Graph(name: project.name,
                          entryPath: path,
                          cache: cache,
                          entryNodes: entryNodes)
        try lint(graph: graph)
        return (workspace, graph)
    }

    func loadWorkspace(path: AbsolutePath) throws -> (WorkspaceStructure, Graph) {
        
        let cache = GraphLoaderCache()
        let circularDetector = GraphCircularDetector()
        let workspace = try WorkspaceStructureFactory(path: path, workspace: try modelLoader.loadWorkspace(at: path)).makeWorkspaceStructure()
        
        func traverseProjects(element: WorkspaceStructure.Element) throws -> [(AbsolutePath, Project)] {
            switch element {
            case .file, .folderReference:
                break
            case .group(name: _, contents: let contents):
                return try contents.flatMap(traverseProjects)
            case let .project(path: path):
                return [try (path, Project.at(path, cache: cache, circularDetector: circularDetector, modelLoader: modelLoader))]
            }
            
            return []
        }


        let projects = try workspace.contents.flatMap(traverseProjects)

        let entryNodes = try projects.flatMap { (project) -> [TargetNode] in
            try project.1.targets.map({ $0.name }).map { targetName in
                try TargetNode.read(name: targetName, path: project.0, cache: cache, circularDetector: circularDetector, modelLoader: modelLoader)
            }
        }
        let graph = Graph(name: workspace.name,
                          entryPath: path,
                          cache: cache,
                          entryNodes: entryNodes)

        try lint(graph: graph)

        return (workspace, graph)
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
    let git: Git
    let fileHandler: FileHandling
    
    init(path: AbsolutePath, fileHandler: FileHandling = FileHandler()) {
        self.path = path
        self.git = GitClient(directory: path)
        self.fileHandler = fileHandler
    }
    
    let includeDotFiles = false
    let includeUntrackedFiles = false
    
    indirect enum Node {
        
        case file(AbsolutePath)
        case directory(AbsolutePath, Graph)
        
    }
    
    internal func buildGraph() throws -> Graph {
        return try buildGraph(path: path)
    }
    
    private func buildGraph(path: AbsolutePath) throws -> Graph {
        
        return try fileHandler.ls(path).compactMap { path in
            
            if includeDotFiles == false && path.basename.hasPrefix(".") {
                return nil
            }
            
            guard includeUntrackedFiles == false && git.isFileBeingTracked(path: path) else {
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
    
    func contentToWorkspaceStructureElement(content: DirectoryStructure.Node) -> WorkspaceStructure.Element? {
        
        switch content {
        case .file(let file):
            return .file(path: file)
        case .directory(let path, _) where path.suffix == ".xcworkspace":
            return nil
        case .directory(let path, _) where path.suffix == ".playground":
            return .file(path: path)
        case .directory(let path, let contents) where contents.files().contains(basename: "Project.swift"):
            return .project(path: path)
        case .directory(let path, let contents) where contents.containsAnyProjectManifestWholeGraphTree():
            return .group(name: path.basename, contents: contents.compactMap(contentToWorkspaceStructureElement))
        case .directory(let path, _):
            return .folderReference(path: path)
        }
        
    }
    
    func makeWorkspaceStructure() throws -> WorkspaceStructure {
        let graph = try DirectoryStructure(path: path).buildGraph()
        return WorkspaceStructure(name: workspace.name, contents: graph.compactMap(contentToWorkspaceStructureElement))
    }
    
}

extension Sequence where Element == AbsolutePath {
    
    func contains(basename: String) -> Bool {
        return self.contains(where: { $0.basename == basename })
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
    
    func containsAnyProjectManifestWholeGraphTree() -> Bool {
        
        return first{ node in
            
            switch node {
            case .file(let path) where path.basename == "Project.swift":
                return true
            case .directory(_, let graph):
                return graph.containsAnyProjectManifestWholeGraphTree()
            case _:
                return false
            }
            
        } != nil
        
    }
    
}
