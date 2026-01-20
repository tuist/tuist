import Foundation

public struct TestCaseRepetition {
    public let repetitionNumber: Int
    public let name: String
    public let status: TestStatus
    public let duration: Int
    public let failures: [TestCaseFailure]

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
