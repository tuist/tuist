import Foundation
import TuistCore

public class MockShell: Shelling {
    public var runStub: (([String], [String: String]) throws -> Void)?
    public var runArgs: [[String]] = []
    public var runCallCount: UInt = 0
    public var runAndOutputStub: (([String], [String: String]) throws -> String)?
    public var runAndOutputArgs: [[String]] = []
    public var runAndOutputCallCount: UInt = 0

    public func run(_ args: String..., environment: [String: String]) throws {
        runArgs.append(args)
        runCallCount += 1
        try runStub?(args, environment)
    }

    public func run(_ args: [String], environment: [String: String]) throws {
        runArgs.append(args)
        runCallCount += 1
        try runStub?(args, environment)
    }

    public func runAndOutput(_ args: String..., environment: [String: String]) throws -> String {
        runAndOutputArgs.append(args)
        runAndOutputCallCount += 1
        return try runAndOutputStub?(args, environment) ?? ""
    }

    public func runAndOutput(_ args: [String], environment: [String: String]) throws -> String {
        runAndOutputArgs.append(args)
        runAndOutputCallCount += 1
        return try runAndOutputStub?(args, environment) ?? ""
    }
}
