import Foundation

public struct TestSummary: Encodable, Sendable {
    public let testPlanName: String?
    public var status: TestStatus
    public let duration: Int?
    public var testModules: [TestModule]
    public let runDestinations: [RunDestination]
    public let errors: [TestRunError]
    /// The coverage held in memory, for a client that sends it inline with the run.
    public var coverage: XcodeCoverageReport?
    /// The coverage streamed to a file of one JSON object per source file (see
    /// `XcodeCoverageParsing.parse(resultBundlePath:manifest:into:)`), with what the bundle said
    /// about the run as a whole. Whoever reads the summary owns the file.
    public var coveragePath: String?
    public var coveragePartial: Bool?
    public var coverageFileCount: Int?
    /// Why the coverage could not be read, for a bundle that had some. The run's tests are
    /// reported either way.
    public var coverageError: String?
    /// `parallel` or `serial`, when the client recorded how the run executed its tests.
    public var executionMode: String?
    /// The tests the run could have executed, when the client enumerated them.
    public var enumeratedTests: [TestEnumeration.Test]?
    /// Which files each test executed, over repository-relative paths, when the client's
    /// coverage observer recorded it.
    public var coverageEvidence: TestCoverageEvidence?

    enum CodingKeys: String, CodingKey {
        case testPlanName = "test_plan_name"
        case status, duration, errors, coverage
        case executionMode = "execution_mode"
        case enumeratedTests = "enumerated_tests"
        case coverageEvidence = "coverage_evidence"
        case coveragePath = "coverage_path"
        case coveragePartial = "coverage_partial"
        case coverageFileCount = "coverage_file_count"
        case coverageError = "coverage_error"
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
        errors: [TestRunError] = [],
        coverage: XcodeCoverageReport? = nil
    ) {
        self.testPlanName = testPlanName
        self.status = status
        self.duration = duration
        self.testModules = testModules
        self.runDestinations = runDestinations
        self.errors = errors
        self.coverage = coverage
    }
}

/// A run/target-level entry that isn't a test failure. xcresult surfaces both
/// kinds as synthetic test cases; we lift them out of the test cases and model
/// them the way Xcode does, as errors keyed by target.
///
/// Runner errors are the test runner itself erroring (e.g. a target whose
/// `.xctest` bundle couldn't be loaded, or the app under test couldn't launch),
/// from "<runner-process> (<pid>) encountered an error" cases, where the runner
/// process is `xctest` for unit tests and the app/UI-runner target for UI tests.
/// They fail the run, as they do for xcodebuild.
///
/// Unattributed issues are Swift Testing issues recorded when no test was
/// running, from "Issues recorded without an associated test or suite" cases.
/// `message` carries the recorded issue, so it can include a source path, a line
/// number, and the asserted expression. They do not fail the run, matching
/// xcodebuild's exit code.
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
