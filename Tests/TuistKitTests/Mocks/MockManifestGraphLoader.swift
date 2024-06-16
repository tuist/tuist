import Foundation
import Path
import TuistCore
import XcodeGraph
@testable import TuistKit

final class MockManifestGraphLoader: ManifestGraphLoading {
    var stubLoadGraph: Graph?
    func load(path _: AbsolutePath) async throws -> (Graph, [SideEffectDescriptor], [LintingIssue]) {
        (stubLoadGraph ?? .test(), [], [])
    }
}
