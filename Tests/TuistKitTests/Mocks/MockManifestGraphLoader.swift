import Foundation
import TSCBasic
import TuistCore
import XcodeGraph
import XcodeGraphTesting
@testable import TuistKit

final class MockManifestGraphLoader: ManifestGraphLoading {
    var stubLoadGraph: Graph?
    func load(path _: AbsolutePath) async throws -> (Graph, [SideEffectDescriptor], [LintingIssue]) {
        (stubLoadGraph ?? .test(), [], [])
    }
}
