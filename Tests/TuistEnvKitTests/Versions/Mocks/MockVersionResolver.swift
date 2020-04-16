import Foundation
import TSCBasic
@testable import TuistEnvKit

class MockVersionResolver: VersionResolving {
    var resolveCallCount: UInt = 0
    var resolveStub: ((AbsolutePath) throws -> ResolvedVersion)?

    func resolve(path: AbsolutePath) throws -> ResolvedVersion {
        resolveCallCount += 1
        return try resolveStub?(path) ?? .undefined
    }
}
