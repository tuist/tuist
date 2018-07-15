import Foundation
import XCTest
import xpmcore

public final class MockErrorHandler: ErrorHandling {
    public var fatalErrorArgs: [FatalError] = []

    public init() {}

    public func fatal(error: FatalError) {
        fatalErrorArgs.append(error)
    }
}
