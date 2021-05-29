import Foundation
import TSCBasic
import TuistSupport

@testable import TuistLoader

final class MockUpRequired: UpRequired {
    var isMetStub: ((AbsolutePath) throws -> Bool)?
    var isMetCallCount: UInt = 0
    var meetStub: ((AbsolutePath) throws -> Void)?
    var meetCallCount: UInt = 0

    override func isMet(projectPath: AbsolutePath) throws -> Bool {
        isMetCallCount += 1
        return try isMetStub?(projectPath) ?? false
    }

    override func meet(projectPath: AbsolutePath) throws {
        meetCallCount += 1
        try meetStub?(projectPath)
    }
}
