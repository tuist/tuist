import Foundation
@testable import TuistEnvKit

final class MockUpdater: Updating {
    var updateCallCount: UInt = 0
    var updateStub: (() throws -> Void)?

    func update() throws {
        updateCallCount += 1
        try updateStub?()
    }
}
