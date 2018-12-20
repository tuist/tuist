import Basic
import Foundation
import TuistCore

@testable import TuistKit

final class MockUp: Upping {
    var isMetStub: ((Systeming, AbsolutePath) throws -> Bool)?
    var isMetCallCount: UInt = 0
    var meetStub: ((Systeming, Printing, AbsolutePath) throws -> Void)?
    var meetCallCount: UInt = 0
    let name: String

    init(name: String = String(describing: MockUp.self)) {
        self.name = name
    }

    func isMet(system: Systeming, projectPath: AbsolutePath) throws -> Bool {
        isMetCallCount += 1
        return try isMetStub?(system, projectPath) ?? false
    }

    func meet(system: Systeming, printer: Printing, projectPath: AbsolutePath) throws {
        meetCallCount += 1
        try meetStub?(system, printer, projectPath)
    }
}
