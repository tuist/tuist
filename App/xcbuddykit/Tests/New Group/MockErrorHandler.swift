import Foundation
@testable import xcbuddykit
import XCTest

final class MockErrorHandler: ErrorHandling {
    var fatalErrorArgs: [FatalError] = []
    var tryStub: ((() throws -> Void) -> Void)?
    var tryErrors: [Error] = []

    func fatal(error: FatalError) {
        fatalErrorArgs.append(error)
    }

    func `try`(_ closure: () throws -> Void) {
        if let tryStub = tryStub {
            tryStub(closure)
        } else {
            do {
                try closure()
            } catch {
                tryErrors.append(error)
            }
        }
    }
}
