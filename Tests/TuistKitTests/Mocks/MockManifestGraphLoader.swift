import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
@testable import TuistKit

final class MockManifestGraphLoader: ManifestGraphLoading {
    var stubLoadGraph: Graph?
    func load(path _: AbsolutePath) async throws -> (Graph, [SideEffectDescriptor]) {
        (stubLoadGraph ?? .test(), [])
    }
}
