import Foundation
@testable import xcbuddykit

class MockShell: Shelling {
    var runStub: (([String]) throws -> String)?

    func run(_ args: String...) throws -> String {
        return try runStub?(args) ?? ""
    }
}
