import Basic
import Foundation

/// Protocol that represents a graph.
protocol Graphing: AnyObject {
    var name: String { get }
    var entryPath: AbsolutePath { get }
    var cache: GraphLoaderCaching { get }
    var entryNodes: [GraphNode] { get }
    var projects: [Project] { get }
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

    init(name: String,
         entryPath: AbsolutePath,
         cache: GraphLoaderCaching,
         entryNodes: [GraphNode]) {
        self.name = name
        self.entryPath = entryPath
        self.cache = cache
        self.entryNodes = entryNodes
    }
    
}
