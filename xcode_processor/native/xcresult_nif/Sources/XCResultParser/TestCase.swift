import Foundation

public struct TestCase: Encodable, Sendable {
    public let name: String
    public let testSuite: String?
    public let module: String?
    public var duration: Int?
    public let status: TestStatus
    public let failures: [TestCaseFailure]
    public let repetitions: [TestCaseRepetition]
    public var crashReport: CrashReport?
    public var attachments: [TestAttachment]

    enum CodingKeys: String, CodingKey {
        case name
        case testSuite = "test_suite"
        case module
        case duration
        case status
        case failures
        case repetitions
        case crashReport = "crash_report"
        case attachments
    }

    public init(
        name: String,
        testSuite: String?,
        module: String?,
        duration: Int?,
        status: TestStatus,
        failures: [TestCaseFailure],
        repetitions: [TestCaseRepetition] = [],
        crashReport: CrashReport? = nil,
        attachments: [TestAttachment] = []
    ) {
        self.name = name
        self.testSuite = testSuite
        self.module = module
        self.duration = duration
        self.status = status
        self.failures = failures
        self.repetitions = repetitions
        self.crashReport = crashReport
        self.attachments = attachments
    }
}
