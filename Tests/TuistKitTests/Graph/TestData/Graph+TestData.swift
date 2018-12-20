import Basic
import Foundation
@testable import TuistKit

extension Graph {
    static func test(name: String = "test",
                     entryPath: AbsolutePath = AbsolutePath("/test/graph"),
                     cache: GraphLoaderCaching = GraphLoaderCache(),
                     entryNodes: [GraphNode] = []) -> Graph {
        return Graph(name: name,
                     entryPath: entryPath,
                     cache: cache,
                     entryNodes: entryNodes)
    }
}
