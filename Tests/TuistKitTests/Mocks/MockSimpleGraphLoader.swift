import Foundation
import TSCBasic
import TuistGraph
import TuistGraphTesting
@testable import TuistKit

final class MockSimpleGraphLoader: SimpleGraphLoading {
    var stubLoadGraph: ValueGraph?
    func loadGraph(at _: AbsolutePath) throws -> ValueGraph {
        stubLoadGraph ?? .test()
    }
}
