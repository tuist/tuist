import Foundation

public struct TestSummary {
    public let testPlanName: String?
    public let status: TestStatus
    public let duration: Int?
    public let testModules: [TestModule]

    public var testCases: [TestCase] {
        testModules.flatMap(\.testCases)
    }

    public init(testPlanName: String?, status: TestStatus, duration: Int?, testModules: [TestModule]) {
        self.testPlanName = testPlanName
        self.status = status
        self.duration = duration
        self.testModules = testModules
    }
}
