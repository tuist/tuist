import Foundation
import TSCBasic
@testable import TuistEnvKit

final class MockBuildCopier: BuildCopying {
    var copyCallCount: UInt = 0
    var copyStub: ((AbsolutePath, AbsolutePath) throws -> Void)?

    func copy(from: AbsolutePath, to: AbsolutePath) throws {
        copyCallCount += 1
        try copyStub?(from, to)
    }
}
