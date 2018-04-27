import Foundation
@testable import xcbuddykit
import XCTest

final class MockErrorHandler: ErrorHandling {
    var fatalErrorArgs: [FatalError] = []

    func fatal(error: FatalError) {
        fatalErrorArgs.append(error)
    }
}
