import Foundation

public enum TestStatus: String, Encodable, Sendable {
    case passed = "success"
    case failed = "failure"
    case skipped
}
