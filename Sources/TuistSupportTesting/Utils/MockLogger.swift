import Foundation
import TuistSupport

public class MockLogger: Logging {
    public var logCount: UInt = 0
    public var logArgs: [String] = []

    public func log(_ message: String) {
        logCount += 1
        logArgs.append(message)
    }
}
