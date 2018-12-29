import Foundation
import TuistCore
import Utility

public final class MockRawCommand: RawCommand {
    public static var command: String = "raw"
    public static var overview: String = "raw command"

    public var runStub: (([String]) throws -> Void)? = { _ in }
    public var runCallCount: UInt = 0

    public init() {}

    public func run(arguments: [String]) throws {
        runCallCount += 1
        try runStub?(arguments)
    }
}
