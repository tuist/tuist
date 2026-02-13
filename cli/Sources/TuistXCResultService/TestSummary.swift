import Foundation

public struct TestSummary {
    public let testPlanName: String?
    public let status: TestStatus
    public let duration: Int?
    public let testModules: [TestModule]
    public let stackTraces: [CrashStackTrace]

    public var testCases: [TestCase] {
        testModules.flatMap(\.testCases)
    }

    public init(
        testPlanName: String?,
        status: TestStatus,
        duration: Int?,
        testModules: [TestModule],
        stackTraces: [CrashStackTrace] = []
    ) {
        self.testPlanName = testPlanName
        self.status = status
        self.duration = duration
        self.testModules = testModules
        self.stackTraces = stackTraces
    }
}
