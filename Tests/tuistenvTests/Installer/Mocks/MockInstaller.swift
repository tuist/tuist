import Foundation
@testable import tuistenv

final class MockInstaller: Installing {
    var installCallCount: UInt = 0
    var installStub: ((String, Bool) throws -> Void)?

    func install(version: String, force: Bool) throws {
        installCallCount += 1
        try installStub?(version, force)
    }
}
