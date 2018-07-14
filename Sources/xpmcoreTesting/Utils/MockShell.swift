import Foundation
import xpmcore

public class MockShell: Shelling {
    public var runStub: (([String], [String: String]) throws -> String)?
    public var runArgs: [[String]] = []

    public func run(_ args: String..., environment: [String: String]) throws -> String {
        runArgs.append(args)
        return try runStub?(args, environment) ?? ""
    }

    public func run(_ args: [String], environment: [String: String]) throws -> String {
        runArgs.append(args)
        return try runStub?(args, environment) ?? ""
    }
}
