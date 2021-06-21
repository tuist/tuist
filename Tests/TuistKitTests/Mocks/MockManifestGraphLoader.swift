import Foundation
import TSCBasic
import TuistGraph
import TuistGraphTesting
@testable import TuistKit

final class MockManifestGraphLoader: ManifestGraphLoading {
    var stubLoadGraph: Graph?
    func loadGraph(at _: AbsolutePath) throws -> Graph {
        stubLoadGraph ?? .test()
    }
}
