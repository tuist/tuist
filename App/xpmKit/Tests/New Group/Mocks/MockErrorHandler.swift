import Foundation
import XCTest
@testable import xpmKit

final class MockErrorHandler: ErrorHandling {
    var fatalErrorArgs: [FatalError] = []

    func fatal(error: FatalError) {
        fatalErrorArgs.append(error)
    }
}
