import Foundation

public enum TestStatus: String, Encodable, Sendable {
    case passed
    case failed
    case skipped
}
