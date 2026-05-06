import Foundation

public struct TestSuite: Encodable, Sendable {
    public let name: String
    public let status: TestStatus
    public let duration: Int

    public init(name: String, status: TestStatus, duration: Int) {
        self.name = name
        self.status = status
        self.duration = duration
    }
}
