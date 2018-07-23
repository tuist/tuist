import Foundation
@testable import TuistEnvKit

final class MockInstaller: Installing {
    var installCallCount: UInt = 0
    var installStub: ((String) throws -> Void)?

    func install(version: String) throws {
        installCallCount += 1
        try installStub?(version)
    }
}
