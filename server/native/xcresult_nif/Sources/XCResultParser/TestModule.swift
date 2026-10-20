import Foundation

public struct TestModule: Encodable, Sendable {
    public let name: String
    public let status: TestStatus
    public let duration: Int
    public let testSuites: [TestSuite]
    public var testCases: [TestCase]
    /// `parallel` or `serial`, when the client recorded how the target's tests executed.
    public var executionMode: String?

    enum CodingKeys: String, CodingKey {
        case name, status, duration
        case testSuites = "test_suites"
        case testCases = "test_cases"
        case executionMode = "execution_mode"
    }

    public init(
        name: String,
        status: TestStatus,
        duration: Int,
        testSuites: [TestSuite],
        testCases: [TestCase],
        executionMode: String? = nil
    ) {
        self.name = name
        self.status = status
        self.duration = duration
        self.testSuites = testSuites
        self.testCases = testCases
        self.executionMode = executionMode
    }
}
