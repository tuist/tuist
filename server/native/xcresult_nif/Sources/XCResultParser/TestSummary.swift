import Foundation

public struct TestSummary: Encodable, Sendable {
    public let testPlanName: String?
    public var status: TestStatus
    public let duration: Int?
    public var testModules: [TestModule]
    public let runDestinations: [RunDestination]
    public let errors: [TestRunError]

    enum CodingKeys: String, CodingKey {
        case testPlanName = "test_plan_name"
        case status, duration, errors
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
        runDestinations: [RunDestination] = [],
        errors: [TestRunError] = []
    ) {
        self.testPlanName = testPlanName
        self.status = status
        self.duration = duration
        self.testModules = testModules
        self.runDestinations = runDestinations
        self.errors = errors
    }
}

/// A run/target-level error that isn't a test failure: the test runner itself
/// errored (e.g. a target whose `.xctest` bundle couldn't be loaded, or the app
/// under test couldn't launch). xcresult surfaces these as synthetic
/// "<runner-process> (<pid>) encountered an error" cases (the runner process is
/// `xctest` for unit tests, the app/UI-runner target for UI tests); we lift them
/// out of the test cases and model them the way Xcode does — as errors, keyed by
/// target.
public struct TestRunError: Encodable, Sendable {
    /// The test target the error belongs to, or nil for a run-level error.
    public let target: String?
    public let message: String

    enum CodingKeys: String, CodingKey {
        case target, message
    }

    public init(target: String?, message: String) {
        self.target = target
        self.message = message
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
