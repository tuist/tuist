import Basic
import Foundation
@testable import TuistEnvKit

final class MockBuildCopier: BuildCopying {
    var copyCallCount: UInt = 0
    var copyStub: ((AbsolutePath, AbsolutePath) throws -> Void)?
    var copyFrameworksArgs: [(from: AbsolutePath, to: AbsolutePath)] = []

    func copy(from: AbsolutePath, to: AbsolutePath) throws {
        copyCallCount += 1
        try copyStub?(from, to)
    }

    func copyFrameworks(from: AbsolutePath, to: AbsolutePath) throws {
        copyFrameworksArgs.append((from: from, to: to))
    }
}
