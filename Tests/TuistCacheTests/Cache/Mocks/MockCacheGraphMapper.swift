import Basic
import Foundation
import TuistCore
import XCTest

@testable import TuistCache
@testable import TuistSupportTesting

final class MockCacheGraphMapper: CacheGraphMapping {
    var mapArgs: [(graph: Graph, xcframeworks: [TargetNode: AbsolutePath])] = []
    var mapStub: Result<Graph, Error>?

    func map(graph: Graph, xcframeworks: [TargetNode: AbsolutePath]) throws -> Graph {
        mapArgs.append((graph: graph, xcframeworks: xcframeworks))
        if let mapStub = mapStub {
            switch mapStub {
            case let .failure(error): throw error
            case let .success(graph): return graph
            }
        } else {
            throw TestError("call to map that has not been stubbed")
        }
    }
}
