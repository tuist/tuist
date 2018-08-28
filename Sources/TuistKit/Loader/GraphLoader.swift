import Basic
import Foundation
import TuistCore

protocol GraphLoading: AnyObject {
    func load(path: AbsolutePath) throws -> Graph
}

class GraphLoader: GraphLoading {

    // MARK: - Attributes

    let linter: GraphLinting
    let printer: Printing
    let fileHandler: FileHandling
    let manifestLoader: GraphManifestLoading

    // MARK: - Init

    init(linter: GraphLinting = GraphLinter(),
         printer: Printing = Printer(),
         fileHandler: FileHandling = FileHandler(),
         manifestLoader: GraphManifestLoading = GraphManifestLoader()) {
        self.linter = linter
        self.printer = printer
        self.fileHandler = fileHandler
        self.manifestLoader = manifestLoader
    }

    func load(path: AbsolutePath) throws -> Graph {
        var graph: Graph!
        let manifests = manifestLoader.manifests(at: path)
        if manifests.contains(.workspace) {
            graph = try loadWorkspace(path: path)
        } else if manifests.contains(.project) {
            graph = try loadProject(path: path)
        } else {
            throw GraphLoadingError.manifestNotFound(path)
        }
        try linter.lint(graph: graph).printAndThrowIfNeeded(printer: printer)
        return graph
    }

    // MARK: - Fileprivate

    fileprivate func loadProject(path: AbsolutePath) throws -> Graph {
        let cache = GraphLoaderCache()
        let circularDetector = GraphCircularDetector()
        let project = try Project.at(path, cache: cache, circularDetector: circularDetector)
        let entryNodes: [GraphNode] = try project.targets.map({ $0.name }).map { targetName in
            return try TargetNode.read(name: targetName, path: path, cache: cache, circularDetector: circularDetector)
        }
        return Graph(name: project.name,
                     entryPath: path,
                     cache: cache,
                     entryNodes: entryNodes)
    }

    fileprivate func loadWorkspace(path: AbsolutePath) throws -> Graph {
        let cache = GraphLoaderCache()
        let circularDetector = GraphCircularDetector()
        let workspace = try Workspace.at(path)
        let projects = try workspace.projects.map { (projectPath) -> (AbsolutePath, Project) in
            return try (projectPath, Project.at(projectPath, cache: cache, circularDetector: circularDetector))
        }
        let entryNodes = try projects.flatMap { (project) -> [TargetNode] in
            return try project.1.targets.map({ $0.name }).map { targetName in
                try TargetNode.read(name: targetName, path: project.0, cache: cache, circularDetector: circularDetector)
            }
        }
        return Graph(name: workspace.name,
                     entryPath: path,
                     cache: cache,
                     entryNodes: entryNodes)
    }
}
