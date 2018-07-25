import Foundation
import TuistCore
import Utility

public final class MockHiddenCommand: HiddenCommand {
    public static var command: String = "hidden"
    public var runStub: (([String]) throws -> Void)? = { _ in }
    public var runCallCount: UInt = 0

    public init() {}

    public func run(arguments: [String]) throws {
        runCallCount += 1
        try runStub?(arguments)
    }
}
