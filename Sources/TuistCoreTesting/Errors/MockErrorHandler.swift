import Foundation
import TuistCore
import XCTest

public final class MockErrorHandler: ErrorHandling {
    public var setupCallCount: UInt = 0
    public var sendEnqueuedErrorsCallCount: UInt = 0
    public var fatalErrorArgs: [FatalError] = []

    public init() {}

    public func setup() throws {
        setupCallCount += 1
    }

    public func fatal(error: FatalError, file _: StaticString = #file, line _: UInt = #line) {
        fatalErrorArgs.append(error)
    }

    public func sendEnqueuedErrors() {
        sendEnqueuedErrorsCallCount += 1
    }
}
