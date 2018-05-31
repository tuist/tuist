import Basic
import Foundation
@testable import xpmKit

final class MockGraphLoader: GraphLoading {
    var loadStub: ((AbsolutePath) throws -> Graph)?

    func load(path: AbsolutePath) throws -> Graph {
        return try loadStub?(path) ?? Graph.test()
    }
}
