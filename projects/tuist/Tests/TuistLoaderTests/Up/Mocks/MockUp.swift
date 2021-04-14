import Foundation
import TSCBasic
import TuistSupport

@testable import TuistLoader

final class MockUp: Upping {
    var isMetStub: ((AbsolutePath) throws -> Bool)?
    var isMetCallCount: UInt = 0
    var meetStub: ((AbsolutePath) throws -> Void)?
    var meetCallCount: UInt = 0
    let name: String

    init(name: String = String(describing: MockUp.self)) {
        self.name = name
    }

    func isMet(projectPath: AbsolutePath) throws -> Bool {
        isMetCallCount += 1
        return try isMetStub?(projectPath) ?? false
    }

    func meet(projectPath: AbsolutePath) throws {
        meetCallCount += 1
        try meetStub?(projectPath)
    }
}
