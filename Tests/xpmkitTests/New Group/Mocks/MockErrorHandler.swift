import Foundation
import XCTest
@testable import xpmkit

final class MockErrorHandler: ErrorHandling {
    var fatalErrorArgs: [FatalError] = []

    func fatal(error: FatalError) {
        fatalErrorArgs.append(error)
    }
}
