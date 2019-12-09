import Basic
import Foundation
import TuistSupport

public protocol GraphLoading: AnyObject {
    /// Path to the directory that contains the project.
    /// - Parameter path: Path to the directory that contains the project.
    func loadProject(path: AbsolutePath) throws -> (Graph, Project)

    /// Loads the graph for the workspace in the given directory.
    /// - Parameter path: Path to the directory that contains the workspace.
    func loadWorkspace(path: AbsolutePath) throws -> (Graph, Workspace)

    /// Loads the TuistConfig.
    ///
    /// - Parameter path: Directory from which look up and load the TuistConfig.
    /// - Returns: Loaded TuistConfig object.
    /// - Throws: An error if the TuistConfig.swift can't be parsed.
    func loadTuistConfig(path: AbsolutePath) throws -> TuistConfig
}

public class GraphLoader: GraphLoading {
    // MARK: - Attributes

    fileprivate let modelLoader: GeneratorModelLoading

    // MARK: - Init

    public init(modelLoader: GeneratorModelLoading) {
        self.modelLoader = modelLoader
    }

    // MARK: - GraphLoading

    public func loadProject(path: AbsolutePath) throws -> (Graph, Project) {
        let graphLoaderCache = GraphLoaderCache()
        let graphCircularDetector = GraphCircularDetector()

        let project = try loadProject(at: path, graphLoaderCache: graphLoaderCache, graphCircularDetector: graphCircularDetector)

        let entryNodes: [GraphNode] = try project.targets.map { target in
            try self.loadTarget(name: target.name, path: path, graphLoaderCache: graphLoaderCache, graphCircularDetector: graphCircularDetector)
        }

        let graph = Graph(name: project.name,
                          entryPath: path,
                          cache: graphLoaderCache,
                          entryNodes: entryNodes)
        return (graph, project)
    }

    public func loadWorkspace(path: AbsolutePath) throws -> (Graph, Workspace) {
        let graphLoaderCache = GraphLoaderCache()
        let graphCircularDetector = GraphCircularDetector()
        let workspace = try modelLoader.loadWorkspace(at: path)

        let projects = try workspace.projects.map { (projectPath) -> (AbsolutePath, Project) in
            try (projectPath, self.loadProject(at: projectPath, graphLoaderCache: graphLoaderCache, graphCircularDetector: graphCircularDetector))
        }

        let entryNodes = try projects.flatMap { (project) -> [TargetNode] in
            let projectPath = project.0
            let projectManifest = project.1
            return try projectManifest.targets.map { target in
                try self.loadTarget(name: target.name, path: projectPath, graphLoaderCache: graphLoaderCache, graphCircularDetector: graphCircularDetector)
            }
        }

        let graph = Graph(name: workspace.name,
                          entryPath: path,
                          cache: graphLoaderCache,
                          entryNodes: entryNodes)
        return (graph, workspace)
    }

    public func loadTuistConfig(path: AbsolutePath) throws -> TuistConfig {
        let cache = GraphLoaderCache()

        if let tuistConfig = cache.tuistConfig(path) {
            return tuistConfig
        } else {
            let tuistConfig = try modelLoader.loadTuistConfig(at: path)
            cache.add(tuistConfig: tuistConfig, path: path)
            return tuistConfig
        }
    }

    // MARK: - Fileprivate

    /// Loads the project at the given path. If the project has already been loaded and cached, it returns it from the cache.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - cache: Graph loading cache.
    ///   - graphCircularDetector: Graph circular detector
    fileprivate func loadProject(at path: AbsolutePath, graphLoaderCache: GraphLoaderCaching, graphCircularDetector: GraphCircularDetecting) throws -> Project {
        if let project = graphLoaderCache.project(path) {
            return project
        } else {
            let project = try modelLoader.loadProject(at: path)
            graphLoaderCache.add(project: project)

            for target in project.targets {
                if graphLoaderCache.targetNode(path, name: target.name) != nil { continue }
                _ = try loadTarget(name: target.name,
                                   path: path,
                                   graphLoaderCache: graphLoaderCache,
                                   graphCircularDetector: graphCircularDetector)
            }

            return project
        }
    }

    /// Loads the given target into the cache.
    /// - Parameters:
    ///   - name: Name of the target to be loaded.
    ///   - path: Path to the directory that contains the project.
    ///   - graphLoaderCache: Graph loader cache.
    ///   - graphCircularDetector: Graph circular dependency detector.
    fileprivate func loadTarget(name: String,
                                path: AbsolutePath,
                                graphLoaderCache: GraphLoaderCaching,
                                graphCircularDetector: GraphCircularDetecting) throws -> TargetNode {
        if let targetNode = graphLoaderCache.targetNode(path, name: name) { return targetNode }

        let project = try loadProject(at: path, graphLoaderCache: graphLoaderCache, graphCircularDetector: graphCircularDetector)

        guard let target = project.targets.first(where: { $0.name == name }) else {
            throw GraphLoadingError.targetNotFound(name, path)
        }

        let targetNode = TargetNode(project: project, target: target, dependencies: [])
        graphLoaderCache.add(targetNode: targetNode)

        let dependencies: [GraphNode] = try target.dependencies.map {
            try loadDependency(for: $0,
                               path: path,
                               name: name,
                               platform: target.platform,
                               graphLoaderCache: graphLoaderCache,
                               graphCircularDetector: graphCircularDetector)
        }

        targetNode.dependencies = dependencies

        try graphCircularDetector.complete()

        return targetNode
    }

    /// Loads a target dependency into the cache.
    /// - Parameters:
    ///   - dependency: Dependency to be loaded.
    ///   - path: Path to the project that defines the dependency.
    ///   - name: Name of the dependency to be loaded.
    ///   - platform: Platform of the target whose dependency is being loaded.
    ///   - graphLoaderCache: Graph loader cache.
    ///   - graphCircularDetector: Graph circular dependency detector.
    fileprivate func loadDependency(for dependency: Dependency,
                                    path: AbsolutePath,
                                    name: String,
                                    platform: Platform,
                                    graphLoaderCache: GraphLoaderCaching,
                                    graphCircularDetector: GraphCircularDetecting) throws -> GraphNode {
        switch dependency {
        // A target within the same project.
        case let .target(target):
            let circularFrom = GraphCircularDetectorNode(path: path, name: name)
            let circularTo = GraphCircularDetectorNode(path: path, name: target)
            graphCircularDetector.start(from: circularFrom, to: circularTo)
            return try loadTarget(name: target, path: path, graphLoaderCache: graphLoaderCache, graphCircularDetector: graphCircularDetector)

        // A target from another project
        case let .project(target, projectPath):
            let circularFrom = GraphCircularDetectorNode(path: path, name: name)
            let circularTo = GraphCircularDetectorNode(path: projectPath, name: target)
            graphCircularDetector.start(from: circularFrom, to: circularTo)
            return try loadTarget(name: target, path: projectPath, graphLoaderCache: graphLoaderCache, graphCircularDetector: graphCircularDetector)

        // Precompiled framework
        case let .framework(frameworkPath):
            return try loadFrameworkNode(frameworkPath: frameworkPath, graphLoaderCache: graphLoaderCache)

        // Precompiled library
        case let .library(libraryPath, publicHeaders, swiftModuleMap):
            return try loadLibraryNode(publicHeaders: publicHeaders,
                                       swiftModuleMap: swiftModuleMap,
                                       libraryPath: libraryPath,
                                       graphLoaderCache: graphLoaderCache)
        // System SDK
        case let .sdk(name, status):
            return try SDKNode(name: name, platform: platform, status: status)

        // CocoaPods
        case let .cocoapods(podsPath):
            return loadCocoaPodsNode(path: podsPath, graphLoaderCache: graphLoaderCache)

        // Swift Package
        case let .package(product):
            return PackageProductNode(product: product, path: path)
        }
    }

    /// Loads the precompiled framework node at the given path.
    /// - Parameters:
    ///   - frameworkPath: Path to the .framework.
    ///   - graphLoaderCache: Graph loader cache.
    fileprivate func loadFrameworkNode(frameworkPath: AbsolutePath, graphLoaderCache: GraphLoaderCaching) throws -> FrameworkNode {
        if let frameworkNode = graphLoaderCache.precompiledNode(frameworkPath) as? FrameworkNode { return frameworkNode }
        let framewokNode = FrameworkNode(path: frameworkPath)
        graphLoaderCache.add(precompiledNode: framewokNode)
        return framewokNode
    }

    /// Loads the precompiled library node at the given paths.
    /// - Parameters:
    ///   - publicHeaders: Path to the directory that contains the public headers.
    ///   - swiftModuleMap: Path to the Swift modulemap file.
    ///   - libraryPath: Path to the library's .a binary.
    ///   - graphLoaderCache: Graph loader cache.
    fileprivate func loadLibraryNode(publicHeaders: AbsolutePath,
                                     swiftModuleMap: AbsolutePath?,
                                     libraryPath: AbsolutePath,
                                     graphLoaderCache: GraphLoaderCaching) throws -> LibraryNode {
        // TODO: Validate using linters
        if !FileHandler.shared.exists(libraryPath) {
            throw GraphLoadingError.missingFile(libraryPath)
        }
        if let libraryNode = graphLoaderCache.precompiledNode(libraryPath) as? LibraryNode { return libraryNode }

        // TODO: Validate using linters
        if !FileHandler.shared.exists(publicHeaders) {
            throw GraphLoadingError.missingFile(publicHeaders)
        }

        // TODO: Validate using linters
        if let swiftModuleMap = swiftModuleMap {
            if !FileHandler.shared.exists(swiftModuleMap) {
                throw GraphLoadingError.missingFile(swiftModuleMap)
            }
        }
        let libraryNode = LibraryNode(path: libraryPath,
                                      publicHeaders: publicHeaders,
                                      swiftModuleMap: swiftModuleMap)
        graphLoaderCache.add(precompiledNode: libraryNode)
        return libraryNode
    }

    /// Loads the CocoaPods node. If it it exists in the cache, it returns it from the cache.
    /// Otherwise, it initializes it, stores it in the cache, and then returns it.
    ///
    /// - Parameters:
    ///   - path: Path to the directory that contains the Podfile.
    ///   - graphLoaderCache: Graph loader cache.
    /// - Returns: The initialized instance of the CocoaPods node.
    fileprivate func loadCocoaPodsNode(path: AbsolutePath,
                                       graphLoaderCache: GraphLoaderCaching) -> CocoaPodsNode {
        if let cached = graphLoaderCache.cocoapods(path) { return cached }
        let node = CocoaPodsNode(path: path)
        graphLoaderCache.add(cocoapods: node)
        return node
    }
}
