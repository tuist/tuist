import Foundation

public struct TestCaseRepetition: Encodable, Sendable {
    public let repetitionNumber: Int
    public let name: String
    public let status: TestStatus
    public let duration: Int
    public let failures: [TestCaseFailure]

    enum CodingKeys: String, CodingKey {
        case repetitionNumber = "repetition_number"
        case name
        case status
        case duration
        case failures
    }

    public init(
        repetitionNumber: Int,
        name: String,
        status: TestStatus,
        duration: Int,
        failures: [TestCaseFailure]
    ) {
        self.repetitionNumber = repetitionNumber
        self.name = name
        self.status = status
        self.duration = duration
        self.failures = failures
    }
}
