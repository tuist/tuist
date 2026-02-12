import Foundation

public struct TestCase {
    public let name: String
    public let testSuite: String?
    public let module: String?
    public var duration: Int?
    public let status: TestStatus
    public let failures: [TestCaseFailure]
    public let repetitions: [TestCaseRepetition]
    public let stackTraceId: String?

    public init(
        name: String,
        testSuite: String?,
        module: String?,
        duration: Int?,
        status: TestStatus,
        failures: [TestCaseFailure],
        repetitions: [TestCaseRepetition] = [],
        stackTraceId: String? = nil
    ) {
        self.name = name
        self.testSuite = testSuite
        self.module = module
        self.duration = duration
        self.status = status
        self.failures = failures
        self.repetitions = repetitions
        self.stackTraceId = stackTraceId
    }
}
