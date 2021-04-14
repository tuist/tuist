import Foundation
import TuistSupport
import XCTest

public final class MockErrorHandler: ErrorHandling {
    public var fatalErrorArgs: [FatalError] = []

    public init() {}

    public func fatal(error: FatalError) {
        fatalErrorArgs.append(error)
    }
}
