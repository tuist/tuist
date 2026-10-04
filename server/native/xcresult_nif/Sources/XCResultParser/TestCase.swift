import Foundation

public struct TestCase: Encodable, Sendable {
    public let name: String
    public let testSuite: String?
    public let module: String?
    public var duration: Int?
    public let status: TestStatus
    public let failures: [TestCaseFailure]
    public let repetitions: [TestCaseRepetition]
    public let arguments: [TestCaseArgument]
    public var crashReport: CrashReport?
    public var attachments: [TestAttachment]
    public var isQuarantined: Bool
    /// The test's name as Swift and `xcodebuild -enumerate-tests` know it, when the result reports
    /// it under another one: a Swift Testing display name (`@Test("Maps paths") func map()`).
    /// Not sent anywhere; it lets the run's enumeration be named after its results.
    public var identifier: String?

    enum CodingKeys: String, CodingKey {
        case name, module, duration, status, failures, repetitions, arguments, attachments
        case testSuite = "test_suite_name"
        case crashReport = "crash_report"
        case isQuarantined = "is_quarantined"
    }

    public init(
        name: String,
        testSuite: String?,
        module: String?,
        duration: Int?,
        status: TestStatus,
        failures: [TestCaseFailure],
        repetitions: [TestCaseRepetition] = [],
        arguments: [TestCaseArgument] = [],
        crashReport: CrashReport? = nil,
        attachments: [TestAttachment] = [],
        isQuarantined: Bool = false,
        identifier: String? = nil
    ) {
        self.name = name
        self.testSuite = testSuite
        self.module = module
        self.duration = duration
        self.status = status
        self.failures = failures
        self.repetitions = repetitions
        self.arguments = arguments
        self.crashReport = crashReport
        self.attachments = attachments
        self.isQuarantined = isQuarantined
        self.identifier = identifier
    }
}
