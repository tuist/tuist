import Foundation

public struct TestModule {
    public let name: String
    public let status: TestStatus
    public let duration: Int
    public let testSuites: [TestSuite]
    public let testCases: [TestCase]

    public init(name: String, status: TestStatus, duration: Int, testSuites: [TestSuite], testCases: [TestCase]) {
        self.name = name
        self.status = status
        self.duration = duration
        self.testSuites = testSuites
        self.testCases = testCases
    }
}
