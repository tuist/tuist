import Foundation

public struct TestModule: Encodable, Sendable {
    public let name: String
    public let status: TestStatus
    public let duration: Int
    public let testSuites: [TestSuite]
    public var testCases: [TestCase]

    enum CodingKeys: String, CodingKey {
        case name
        case status
        case duration
        case testSuites = "test_suites"
        case testCases = "test_cases"
    }

    public init(
        name: String, status: TestStatus, duration: Int, testSuites: [TestSuite],
        testCases: [TestCase]
    ) {
        self.name = name
        self.status = status
        self.duration = duration
        self.testSuites = testSuites
        self.testCases = testCases
    }
}
