import Foundation

public struct TestSummary: Encodable, Sendable {
    public let testPlanName: String?
    public var status: TestStatus
    public let duration: Int?
    public var testModules: [TestModule]

    enum CodingKeys: String, CodingKey {
        case testPlanName = "test_plan_name"
        case status, duration
        case testModules = "test_modules"
    }

    public var testCases: [TestCase] {
        testModules.flatMap(\.testCases)
    }

    public init(
        testPlanName: String?,
        status: TestStatus,
        duration: Int?,
        testModules: [TestModule]
    ) {
        self.testPlanName = testPlanName
        self.status = status
        self.duration = duration
        self.testModules = testModules
    }
}
