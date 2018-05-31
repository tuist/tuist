import Foundation
@testable import xpmKit
import XCTest

final class MockErrorHandler: ErrorHandling {
    var fatalErrorArgs: [FatalError] = []

    func fatal(error: FatalError) {
        fatalErrorArgs.append(error)
    }
}
