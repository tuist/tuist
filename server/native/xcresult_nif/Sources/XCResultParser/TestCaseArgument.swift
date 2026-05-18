import Foundation

public struct TestCaseArgument: Encodable, Sendable {
    public let name: String
    public let status: TestStatus
    public let duration: Int
    public let failures: [TestCaseFailure]
    public let repetitions: [TestCaseRepetition]

    public init(
        name: String,
        status: TestStatus,
        duration: Int,
        failures: [TestCaseFailure],
        repetitions: [TestCaseRepetition]
    ) {
        self.name = name
        self.status = status
        self.duration = duration
        self.failures = failures
        self.repetitions = repetitions
    }
}
