import Basic
import Foundation
import TuistSupport

protocol GraphLoading: AnyObject {
    func loadProject(path: AbsolutePath) throws -> (Graph, Project)
    func loadWorkspace(path: AbsolutePath) throws -> (Graph, Workspace)

    /// Loads the TuistConfig.
    ///
    /// - Parameter path: Directory from which look up and load the TuistConfig.
    /// - Returns: Loaded TuistConfig object.
    /// - Throws: An error if the TuistConfig.swift can't be parsed.
    func loadTuistConfig(path: AbsolutePath) throws -> TuistConfig
}

class GraphLoader: GraphLoading {
    // MARK: - Attributes

    let linter: GraphLinting?
    let modelLoader: GeneratorModelLoading

    // MARK: - Init

    convenience init(modelLoader: GeneratorModelLoading) {
        self.init(linter: GraphLinter(),
                  modelLoader: modelLoader)
    }

    init(linter: GraphLinting? = nil,
         modelLoader: GeneratorModelLoading) {
        self.linter = linter
        self.modelLoader = modelLoader
    }

    func loadProject(path: AbsolutePath) throws -> (Graph, Project) {
        let cache = GraphLoaderCache()
        let circularDetector = GraphCircularDetector()
        let project = try Project.at(path, cache: cache, circularDetector: circularDetector, modelLoader: modelLoader)
        let entryNodes: [GraphNode] = try project.targets.map { target in
            try TargetNode.read(name: target.name, path: path, cache: cache, circularDetector: circularDetector, modelLoader: modelLoader)
        }
        let graph = Graph(name: project.name,
                          entryPath: path,
                          cache: cache,
                          entryNodes: entryNodes)
        try lint(graph: graph)
        return (graph, project)
    }

    func loadWorkspace(path: AbsolutePath) throws -> (Graph, Workspace) {
        let cache = GraphLoaderCache()
        let circularDetector = GraphCircularDetector()
        let workspace = try modelLoader.loadWorkspace(at: path)
        let projects = try workspace.projects.map { (projectPath) -> (AbsolutePath, Project) in
            try (projectPath, Project.at(projectPath, cache: cache, circularDetector: circularDetector, modelLoader: modelLoader))
        }
        let entryNodes = try projects.flatMap { (project) -> [TargetNode] in
            try project.1.targets.map { target in
                try TargetNode.read(name: target.name, path: project.0, cache: cache, circularDetector: circularDetector, modelLoader: modelLoader)
            }
        }
        let graph = Graph(name: workspace.name,
                          entryPath: path,
                          cache: cache,
                          entryNodes: entryNodes)

        try lint(graph: graph)
        return (graph, workspace)
    }

    /// Loads the TuistConfig.
    ///
    /// - Parameter path: Directory from which look up and load the TuistConfig.
    /// - Returns: Loaded TuistConfig object.
    /// - Throws: An error if the TuistConfig.swift can't be parsed.
    func loadTuistConfig(path: AbsolutePath) throws -> TuistConfig {
        let cache = GraphLoaderCache()
        return try TuistConfig.at(path,
                                  cache: cache,
                                  modelLoader: modelLoader)
    }

    private func lint(graph: Graph) throws {
        try linter?.lint(graph: graph).printAndThrowIfNeeded()
    }
}
