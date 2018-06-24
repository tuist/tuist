import Foundation
@testable import xpmkit

class MockLogger: Logging {
    var logCount: UInt = 0
    var logArgs: [String] = []

    func log(_ message: String) {
        logCount += 1
        logArgs.append(message)
    }
}
