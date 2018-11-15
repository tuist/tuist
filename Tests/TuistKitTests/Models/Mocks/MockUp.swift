import Basic
import Foundation
import TuistCore

@testable import TuistKit

final class MockUp: Upping {
    var isMetStub: ((Systeming, AbsolutePath) throws -> Bool)?
    var meetStub: ((Systeming, Printing, AbsolutePath) throws -> Void)?
    var name: String = String(describing: MockUp.self)

    func isMet(system: Systeming, projectPath: AbsolutePath) throws -> Bool {
        return try isMetStub?(system, projectPath) ?? false
    }

    func meet(system: Systeming, printer: Printing, projectPath: AbsolutePath) throws {
        try meetStub?(system, printer, projectPath)
    }
}
