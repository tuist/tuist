import Foundation
import xpmcore

public class MockShell: Shelling {
    public var runStub: (([String], [String: String]) throws -> Void)?
    public var runArgs: [[String]] = []
    public var runAndOutputStub: (([String], [String: String]) throws -> String)?
    public var runAndOutputArgs: [[String]] = []

    public func run(_ args: String..., environment: [String: String]) throws {
        runArgs.append(args)
        try runStub?(args, environment)
    }

    public func run(_ args: [String], environment: [String: String]) throws {
        runArgs.append(args)
        try runStub?(args, environment)
    }

    public func runAndOutput(_ args: String..., environment: [String: String]) throws -> String {
        runAndOutputArgs.append(args)
        return try runAndOutputStub?(args, environment) ?? ""
    }

    public func runAndOutput(_ args: [String], environment: [String: String]) throws -> String {
        runAndOutputArgs.append(args)
        return try runAndOutputStub?(args, environment) ?? ""
    }
}
