import Foundation

protocol GraphControlling: AnyObject {
    // TODO:
}

class GraphController: GraphControlling {
    let cache: GraphLoaderCaching
    let entryNodes: [GraphNode]

    init(cache: GraphLoaderCaching,
         entryNodes: [GraphNode]) {
        self.cache = cache
        self.entryNodes = entryNodes
    }
}
