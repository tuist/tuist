import Foundation
@testable import TuistEnvKit

final class MockUpdater: Updating {
    var updateCallCount: UInt = 0
    var updateStub: ((Bool) throws -> Void)?

    func update(force: Bool) throws {
        updateCallCount += 1
        try updateStub?(force)
    }
}
