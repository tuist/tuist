import Foundation
@testable import TuistEnvKit

final class MockEnvUpdater: EnvUpdating {
    var updateCallCount: UInt = 0
    var updateStub: (() throws -> Void)?

    func update() throws {
        updateCallCount += 1
        try updateStub?()
    }
}
