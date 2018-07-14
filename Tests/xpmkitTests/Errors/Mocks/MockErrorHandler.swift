import Foundation
import XCTest
import xpmcore
@testable import xpmkit

final class MockErrorHandler: ErrorHandling {
    var fatalErrorArgs: [FatalError] = []

    func fatal(error: FatalError) {
        fatalErrorArgs.append(error)
    }
}
