import Foundation
@testable import xcbuddykit

class MockShell: Shelling {
    var runStub: (([String], [String: String]) throws -> String)?
    var runArgs: [[String]] = []

    func run(_ args: String..., environment: [String: String]) throws -> String {
        runArgs.append(args)
        return try runStub?(args, environment) ?? ""
    }

    func run(_ args: [String], environment: [String: String]) throws -> String {
        runArgs.append(args)
        return try runStub?(args, environment) ?? ""
    }
}
