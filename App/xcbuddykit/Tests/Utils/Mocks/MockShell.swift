import Foundation
@testable import xcbuddykit

class MockShell: Shelling {
    var runStub: (([String]) throws -> String)?
    var runArgs: [[String]] = []

    func run(_ args: String...) throws -> String {
        runArgs.append(args)
        return try runStub?(args) ?? ""
    }
}
