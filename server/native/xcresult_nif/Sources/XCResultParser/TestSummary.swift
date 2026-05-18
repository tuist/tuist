import Foundation

public struct TestSummary: Encodable, Sendable {
    public let testPlanName: String?
    public var status: TestStatus
    public let duration: Int?
    public var testModules: [TestModule]
    public let runDestinations: [RunDestination]

    enum CodingKeys: String, CodingKey {
        case testPlanName = "test_plan_name"
        case status, duration
        case testModules = "test_modules"
        case runDestinations = "run_destinations"
    }

    public var testCases: [TestCase] {
        testModules.flatMap(\.testCases)
    }

    public init(
        testPlanName: String?,
        status: TestStatus,
        duration: Int?,
        testModules: [TestModule],
        runDestinations: [RunDestination] = []
    ) {
        self.testPlanName = testPlanName
        self.status = status
        self.duration = duration
        self.testModules = testModules
        self.runDestinations = runDestinations
    }
}

public struct RunDestination: Encodable, Sendable {
    public let name: String
    public let platform: String
    public let osVersion: String

    enum CodingKeys: String, CodingKey {
        case name
        case platform
        case osVersion = "os_version"
    }

    public init(name: String, platform: String, osVersion: String) {
        self.name = name
        self.platform = platform
        self.osVersion = osVersion
    }
}
