import Foundation
@testable import TuistEnvKit

final class MockCommandRunner: CommandRunning {
    var runCallCount: UInt = 0
    var runStub: Error?

    func run() throws {
        runCallCount += 1
        if let runStub = runStub { throw runStub }
    }
}
