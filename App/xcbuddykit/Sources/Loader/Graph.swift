import Basic
import Foundation

/// Protocol that represents a graph.
protocol Graphing: AnyObject {
    var name: String { get }
    var entryPath: AbsolutePath { get }
    var cache: GraphLoaderCaching { get }
    var entryNodes: [GraphNode] { get }
    var projects: [Project] { get }
    func linkableDependencies(path: AbsolutePath, name: String) -> [AbsolutePath]
    func dependenciesPublicHeaders(path: AbsolutePath, name: String) -> [AbsolutePath]
    func embeddableFrameworks(path: AbsolutePath, name: String, shell: Shelling) throws -> [AbsolutePath]
}

/// Graph representation.
class Graph: Graphing {
    /// Graph name.
    let name: String

    /// Entry path (directory)
    let entryPath: AbsolutePath

    /// Cache.
    let cache: GraphLoaderCaching

    /// Entry nodes.
    let entryNodes: [GraphNode]

    /// Graph projects.
    var projects: [Project] {
        return Array(cache.projects.values)
    }

    /// Initializes the graph with its attributes.
    ///
    /// - Parameters:
    ///   - name: graph name.
    ///   - entryPath: path to the folder that contains the entry point manifest.
    ///   - cache: graph cache.
    ///   - entryNodes: nodes that are defined in the entry point manifest.
    init(name: String,
         entryPath: AbsolutePath,
         cache: GraphLoaderCaching,
         entryNodes: [GraphNode]) {
        self.name = name
        self.entryPath = entryPath
        self.cache = cache
        self.entryNodes = entryNodes
    }

    /// Given a target, it returns the list of dependencies that should be linked from it.
    ///
    /// - Parameters:
    ///   - path: path to the folder that contains the manifest where the target is defined.
    ///   - name: target name.
    /// - Returns: paths to the linkable dependencies (.framework & .a)
    func linkableDependencies(path: AbsolutePath, name: String) -> [AbsolutePath] {
        guard let targetNodes = cache.targetNodes[path] else { return [] }
        guard let targetNode = targetNodes[name] else { return [] }
        return targetNode
            .dependencies
            .compactMap({ $0 as? PrecompiledNode })
            .map({ $0.path })
    }

    /// Given a target, it returns the list of public headers folders that should be
    /// exposed to the target.
    ///
    /// - Parameters:
    ///   - path: path to the folder that contains the manifest where the target is defined.
    ///   - name: target name.
    /// - Returns: paths to the public headers folders.
    func dependenciesPublicHeaders(path: AbsolutePath, name: String) -> [AbsolutePath] {
        guard let targetNodes = cache.targetNodes[path] else { return [] }
        guard let targetNode = targetNodes[name] else { return [] }
        return targetNode
            .dependencies
            .compactMap({ $0 as? LibraryNode })
            .map({ $0.publicHeaders })
    }

    /// Given a target, it returns the list of frameworks that should be embedded into the
    /// frameworks folder of the target product.
    ///
    /// - Parameters:
    ///   - path: path to the folder that contains the manifest where the target is defined.
    ///   - name: target name.
    ///   - shell: shell util.
    /// - Returns: paths to the frameworks that should be embedded.
    /// - Throws: an error is thrown while trying to get whether a framework is static or dynamic.
    func embeddableFrameworks(path: AbsolutePath, name: String, shell: Shelling) throws -> [AbsolutePath] {
        guard let targetNodes = cache.targetNodes[path] else { return [] }
        guard let targetNode = targetNodes[name] else { return [] }
        if targetNode.target.product != .app { return [] }
        return try targetNode
            .dependencies
            .compactMap({ $0 as? FrameworkNode })
            .filter({ try $0.linking(shell: shell) == .dynamic })
            .map({ $0.path })
    }
}
