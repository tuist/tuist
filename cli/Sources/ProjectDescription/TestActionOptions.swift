/// The order in which Xcode executes tests in a test plan (from Xcode 15).
public enum TestExecutionOrdering: String, Codable, Sendable {
    /// Run tests in alphabetical order.
    case alphabetical

    /// Run tests in a random order.
    case random
}

/// The global parallelization mode for a generated test plan (from Xcode 16).
public enum TestPlanParallelizationMode: String, Codable, Sendable {
    /// Let Xcode choose the parallelization mode.
    case automatic

    /// Run tests serially.
    case disabled

    /// Run tests in parallel.
    case enabled

    /// Run only Swift Testing tests in parallel.
    case swiftTestingOnly
}

/// The repetition policy Xcode applies to each test (from Xcode 15).
public enum TestRepetitionMode: String, Codable, Sendable {
    /// Run every test once.
    case none

    /// Keep running a test until it fails.
    case untilFailure

    /// Run failed tests again.
    case retryOnFailure
}

/// How long Xcode retains test attachments (from Xcode 15).
public enum TestAttachmentLifetime: String, Codable, Sendable {
    /// Keep every attachment.
    case keepAlways

    /// Delete attachments for successful tests.
    case deleteOnSuccess

    /// Delete every attachment.
    case keepNever
}

/// When Xcode collects diagnostics while executing tests (from Xcode 15).
public enum TestDiagnosticCollectionPolicy: String, Codable, Sendable {
    /// Never collect diagnostics.
    case never = "Never"

    /// Collect diagnostics when a test fails.
    case onFailure = "OnFailure"
}

/// The degree of interoperability between Swift Testing and XCTest (from Xcode 27).
public enum TestInteropMode: String, Codable, Sendable {
    /// Report assertion failures across framework boundaries as warnings.
    case limited

    /// Treat assertion failures across framework boundaries as test failures.
    case complete
}

/// How Xcode treats UI application crashes while tests run (from Xcode 27).
public enum ApplicationCrashDetectionSeverity: String, Codable, Sendable {
    /// Do not detect application crashes.
    case disabled

    /// Report application crashes as warnings.
    case warning

    /// Report application crashes as test failures.
    case failure

    /// Report application crashes as fatal test failures.
    case fatalFailure
}

/// A location simulated while running tests (from Xcode 15).
public struct TestLocationScenario: Equatable, Codable, Sendable {
    /// The scenario identifier shown by Xcode.
    public let identifier: String

    /// The kind of location scenario reference understood by Xcode.
    public let referenceType: String

    /// Creates a location scenario reference.
    public init(identifier: String, referenceType: String = "built-in") {
        self.identifier = identifier
        self.referenceType = referenceType
    }
}

/// The type `TestActionOptions` represents a set of options for a test action.
public struct TestActionOptions: Equatable, Codable, Sendable {
    /// Language used to run the tests (from Xcode 15).
    public var language: SchemeLanguage?

    /// Region used to run the tests (from Xcode 15).
    public var region: String?

    /// Preferred screen capture format for UI tests results (from Xcode 15).
    public var preferredScreenCaptureFormat: ScreenCaptureFormat?

    /// Whether the scheme should or not gather the test coverage data (from Xcode 15).
    public var coverage: Bool

    /// A list of targets you want to gather the test coverage data for them, which are defined in the project (from Xcode 15).
    public var codeCoverageTargets: [TargetReference]

    /// The order in which Xcode executes the tests (from Xcode 15).
    public var testExecutionOrdering: TestExecutionOrdering

    /// The global parallelization mode for the plan (from Xcode 16).
    public var parallelizationMode: TestPlanParallelizationMode?

    /// The policy used to repeat tests (from Xcode 15).
    public var testRepetitionMode: TestRepetitionMode

    /// The maximum number of test repetitions when repetition is enabled (from Xcode 15).
    public var maximumTestRepetitions: Int?

    /// Whether each test repetition runs in a new runner process (from Xcode 15).
    public var repeatInNewRunnerProcess: Bool

    /// Whether test timeouts are enabled (from Xcode 15).
    public var testTimeoutsEnabled: Bool

    /// The default per-test timeout in seconds (from Xcode 15).
    public var defaultTestExecutionTimeAllowance: Int?

    /// The maximum permitted per-test timeout in seconds (from Xcode 15).
    public var maximumTestExecutionTimeAllowance: Int?

    /// How long user-created attachments are retained (from Xcode 15).
    public var userAttachmentLifetime: TestAttachmentLifetime

    /// How long UI-testing screenshots are retained (from Xcode 15).
    public var uiTestingScreenshotsLifetime: TestAttachmentLifetime

    /// Whether Xcode captures screenshots for localization issues (from Xcode 15).
    public var areLocalizationScreenshotsEnabled: Bool

    /// When Xcode collects diagnostics during the test run (from Xcode 15).
    public var diagnosticCollectionPolicy: TestDiagnosticCollectionPolicy

    /// The distribution service identifier used for the test run (from Xcode 15).
    public var distributor: String?

    /// The location scenario simulated during the test run (from Xcode 15).
    public var locationScenario: TestLocationScenario?

    /// The interoperability mode between Swift Testing and XCTest (from Xcode 27).
    public var testInteropMode: TestInteropMode?

    /// How Xcode treats UI application crashes during testing (from Xcode 27).
    public var applicationCrashDetectionSeverity: ApplicationCrashDetectionSeverity?

    /// Returns a set of options for a test action.
    /// - Parameters:
    ///   - language: Language used for running the tests.
    ///   - region: Region used for running the tests.
    ///   - preferredScreenCaptureFormat: The format used for UI-test screen captures.
    ///   - coverage: Whether test coverage should be collected.
    ///   - codeCoverageTargets: List of test targets whose code coverage information should be collected.
    ///   - testExecutionOrdering: The order in which Xcode executes tests.
    ///   - parallelizationMode: The global parallelization mode for the plan.
    ///   - testRepetitionMode: The policy used to repeat tests.
    ///   - maximumTestRepetitions: The maximum number of repetitions for each test.
    ///   - repeatInNewRunnerProcess: Whether repetitions use a fresh runner process.
    ///   - testTimeoutsEnabled: Whether test timeouts are enabled.
    ///   - defaultTestExecutionTimeAllowance: The default per-test timeout in seconds.
    ///   - maximumTestExecutionTimeAllowance: The maximum permitted per-test timeout in seconds.
    ///   - userAttachmentLifetime: How long user-created attachments are retained.
    ///   - uiTestingScreenshotsLifetime: How long UI-testing screenshots are retained.
    ///   - areLocalizationScreenshotsEnabled: Whether localization screenshots are captured.
    ///   - diagnosticCollectionPolicy: When Xcode collects diagnostics.
    ///   - distributor: The distribution service identifier used by Xcode.
    ///   - locationScenario: The location scenario simulated during tests.
    ///   - testInteropMode: The interoperability mode between Swift Testing and XCTest.
    ///   - applicationCrashDetectionSeverity: How Xcode treats UI application crashes during testing.
    /// - Returns: A set of options.
    public static func options(
        language: SchemeLanguage? = nil,
        region: String? = nil,
        preferredScreenCaptureFormat: ScreenCaptureFormat? = nil,
        coverage: Bool = false,
        codeCoverageTargets: [TargetReference] = [],
        testExecutionOrdering: TestExecutionOrdering = .alphabetical,
        parallelizationMode: TestPlanParallelizationMode? = nil,
        testRepetitionMode: TestRepetitionMode = .none,
        maximumTestRepetitions: Int? = nil,
        repeatInNewRunnerProcess: Bool = false,
        testTimeoutsEnabled: Bool = true,
        defaultTestExecutionTimeAllowance: Int? = nil,
        maximumTestExecutionTimeAllowance: Int? = nil,
        userAttachmentLifetime: TestAttachmentLifetime = .deleteOnSuccess,
        uiTestingScreenshotsLifetime: TestAttachmentLifetime = .deleteOnSuccess,
        areLocalizationScreenshotsEnabled: Bool = false,
        diagnosticCollectionPolicy: TestDiagnosticCollectionPolicy = .never,
        distributor: String? = nil,
        locationScenario: TestLocationScenario? = nil,
        testInteropMode: TestInteropMode? = nil,
        applicationCrashDetectionSeverity: ApplicationCrashDetectionSeverity? = nil
    ) -> TestActionOptions {
        TestActionOptions(
            language: language,
            region: region,
            preferredScreenCaptureFormat: preferredScreenCaptureFormat,
            coverage: coverage,
            codeCoverageTargets: codeCoverageTargets,
            testExecutionOrdering: testExecutionOrdering,
            parallelizationMode: parallelizationMode,
            testRepetitionMode: testRepetitionMode,
            maximumTestRepetitions: maximumTestRepetitions,
            repeatInNewRunnerProcess: repeatInNewRunnerProcess,
            testTimeoutsEnabled: testTimeoutsEnabled,
            defaultTestExecutionTimeAllowance: defaultTestExecutionTimeAllowance,
            maximumTestExecutionTimeAllowance: maximumTestExecutionTimeAllowance,
            userAttachmentLifetime: userAttachmentLifetime,
            uiTestingScreenshotsLifetime: uiTestingScreenshotsLifetime,
            areLocalizationScreenshotsEnabled: areLocalizationScreenshotsEnabled,
            diagnosticCollectionPolicy: diagnosticCollectionPolicy,
            distributor: distributor,
            locationScenario: locationScenario,
            testInteropMode: testInteropMode,
            applicationCrashDetectionSeverity: applicationCrashDetectionSeverity
        )
    }
}
