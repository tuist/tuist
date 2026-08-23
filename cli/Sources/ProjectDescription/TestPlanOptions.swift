/// The distribution service used by Xcode when running a test plan.
public enum TestPlanDistributor: String, Codable, Sendable {
    /// Run tests using an App Store build.
    case appStore = "com.apple.AppStore"
    /// Run tests using a TestFlight build.
    case testFlight = "com.apple.TestFlight"
}

/// The allocation subset for which Xcode records Malloc stack traces in a test plan.
public enum TestPlanMallocStackLogging: String, Codable, Sendable {
    /// Record stack traces for every allocation.
    case allAllocations
    /// Record stack traces only for allocations that remain live.
    case liveAllocations
}

/// The severity Xcode assigns to a runtime issue in a test plan.
public enum TestPlanRuntimeIssueSeverity: String, Codable, Sendable {
    /// Report the issue as a warning.
    case warning
    /// Report the issue as an error.
    case error
}

/// The code-coverage mode Xcode uses while executing a test plan.
public enum TestPlanCodeCoverage: Equatable, Codable, Sendable {
    /// Do not collect code coverage.
    case disabled
    /// Collect code coverage for every eligible target.
    case allTargets
    /// Collect code coverage only for the given targets.
    case specificTargets([TargetReference])
}

/// The Address Sanitizer mode Xcode uses while executing a test plan.
public enum TestPlanAddressSanitizer: Equatable, Codable, Sendable {
    /// Do not enable Address Sanitizer.
    case disabled
    /// Enable Address Sanitizer and select whether to detect stack use after return.
    case enabled(detectStackUseAfterReturn: Bool)
}

/// The Checked Allocations mode Xcode uses while executing a test plan.
public enum TestPlanCheckedAllocations: String, Codable, Sendable {
    /// Do not enable Checked Allocations.
    case disabled
    /// Check allocations on every supported destination.
    case always
    /// Check allocations only on destinations with hardware acceleration.
    case mteOnly
}

/// The runtime-issue detection policy Xcode applies while executing a test plan.
public enum TestPlanRuntimeIssueDetectionPolicy: Equatable, Codable, Sendable {
    /// Do not report this category of runtime issues.
    case disabled
    /// Report this category of runtime issues at the given severity.
    case enabled(TestPlanRuntimeIssueSeverity)
}

/// The kind of location scenario reference understood by Xcode.
public enum TestLocationScenarioReferenceType: String, Codable, Sendable {
    /// A scenario shipped with Xcode.
    case builtIn = "built-in"
    /// A scenario stored in the project.
    case custom
}

/// A location simulated while running a test plan.
public struct TestPlanLocationScenario: Equatable, Codable, Sendable {
    /// The Xcode location scenario identifier.
    public let identifier: String
    /// The source from which Xcode resolves the scenario.
    public let referenceType: TestLocationScenarioReferenceType

    /// Creates a location scenario.
    public init(
        identifier: String,
        referenceType: TestLocationScenarioReferenceType = .builtIn
    ) {
        self.identifier = identifier
        self.referenceType = referenceType
    }
}

/// Explicit base or per-configuration options for a generated `.xctestplan`.
///
/// Every property is optional. `nil` means that Tuist omits the key and lets Xcode apply its
/// own default; an explicit `false` is preserved in the generated JSON. To discover additional
/// Xcode fields, inspect a plan saved by Xcode and `IDETestPlan.BaseOptions` in
/// `IDEFoundation.framework` as described in `TestPlan.swift`.
public struct TestPlanOptions: Equatable, Codable, Sendable {
    /// The command-line arguments and environment variables passed to the test process.
    public var arguments: Arguments?
    /// The code-coverage mode used while running tests.
    public var codeCoverage: TestPlanCodeCoverage?
    /// The target from which Xcode expands build-setting variables in the test plan.
    public var expandVariableFromTarget: TargetReference?
    /// The language used while running tests.
    public var language: SchemeLanguage?
    /// The locale region used while running tests.
    public var region: String?
    /// The format used for screenshots captured while running tests.
    public var preferredScreenCaptureFormat: ScreenCaptureFormat?
    /// The order in which Xcode executes tests.
    public var testExecutionOrdering: TestExecutionOrdering?
    /// The global mode Xcode uses to parallelize test execution.
    public var parallelizationMode: TestPlanParallelizationMode?
    /// The mode Xcode uses to repeat tests.
    public var testRepetitionMode: TestRepetitionMode?
    /// The maximum number of times Xcode repeats a test.
    public var maximumTestRepetitions: Int?
    /// Whether Xcode starts a new runner process for every test repetition.
    public var repeatInNewRunnerProcess: Bool?
    /// Whether Xcode enforces per-test execution timeouts.
    public var testTimeoutsEnabled: Bool?
    /// The default per-test execution timeout, in seconds.
    public var defaultTestExecutionTimeAllowance: Int?
    /// The maximum per-test execution timeout, in seconds.
    public var maximumTestExecutionTimeAllowance: Int?
    /// How long Xcode retains attachments created by tests.
    public var userAttachmentLifetime: TestAttachmentLifetime?
    /// How long Xcode retains screenshots created by UI tests.
    public var uiTestingScreenshotsLifetime: TestAttachmentLifetime?
    /// Whether Xcode captures screenshots while running localization tests.
    public var areLocalizationScreenshotsEnabled: Bool?
    /// The diagnostics Xcode collects while running tests.
    public var diagnosticCollectionPolicy: TestDiagnosticCollectionPolicy?
    /// The distribution service Xcode uses to run tests.
    public var distributor: TestPlanDistributor?
    /// The simulated location scenario used while running tests.
    public var locationScenario: TestPlanLocationScenario?
    /// The interoperability mode between Swift Testing and XCTest.
    public var testInteropMode: TestInteropMode?
    /// The severity at which Xcode reports an application crash during UI tests.
    public var applicationCrashDetectionSeverity: ApplicationCrashDetectionSeverity?
    /// The Address Sanitizer mode used while running tests.
    public var addressSanitizer: TestPlanAddressSanitizer?
    /// Whether Xcode enables Thread Sanitizer.
    public var threadSanitizerEnabled: Bool?
    /// Whether Xcode enables Main Thread Checker.
    public var mainThreadCheckerEnabled: Bool?
    /// Whether Xcode enables Thread Performance Checker.
    public var performanceAntipatternCheckerEnabled: Bool?
    /// Whether Xcode enables Undefined Behavior Sanitizer.
    public var undefinedBehaviorSanitizerEnabled: Bool?
    /// Whether Xcode enables Zombie Objects.
    public var zombieObjectsEnabled: Bool?
    /// Whether Xcode enables Guard Malloc.
    public var guardMallocEnabled: Bool?
    /// Whether Xcode fills allocated and deallocated memory with recognizable byte patterns.
    public var mallocScribbleEnabled: Bool?
    /// Whether Xcode places guard edges around heap allocations.
    public var mallocGuardEdgesEnabled: Bool?
    /// The allocations for which Xcode records Malloc stack traces.
    public var mallocStackLogging: TestPlanMallocStackLogging?
    /// The Checked Allocations mode used while running tests.
    public var checkedAllocations: TestPlanCheckedAllocations?
    /// The policy for runtime issues other than Main Thread and Thread Performance Checker issues.
    public var runtimeIssueDetection: TestPlanRuntimeIssueDetectionPolicy?
    /// The policy for Main Thread Checker runtime issues.
    public var mainThreadCheckerDetectionPolicy: TestPlanRuntimeIssueDetectionPolicy?
    /// The policy for Thread Performance Checker runtime issues.
    public var threadPerformanceCheckerRuntimeIssueDetection: TestPlanRuntimeIssueDetectionPolicy?
    /// Whether Xcode enables Memory Tagging Address Sanitizer.
    public var memoryTaggingAddressSanitizerEnabled: Bool?

    /// Creates generated test-plan options. Every argument defaults to `nil`, so Xcode defaults
    /// are never serialized unless the manifest explicitly selects a value.
    public static func options(
        arguments: Arguments? = nil,
        codeCoverage: TestPlanCodeCoverage? = nil,
        expandVariableFromTarget: TargetReference? = nil,
        language: SchemeLanguage? = nil,
        region: String? = nil,
        preferredScreenCaptureFormat: ScreenCaptureFormat? = nil,
        testExecutionOrdering: TestExecutionOrdering? = nil,
        parallelizationMode: TestPlanParallelizationMode? = nil,
        testRepetitionMode: TestRepetitionMode? = nil,
        maximumTestRepetitions: Int? = nil,
        repeatInNewRunnerProcess: Bool? = nil,
        testTimeoutsEnabled: Bool? = nil,
        defaultTestExecutionTimeAllowance: Int? = nil,
        maximumTestExecutionTimeAllowance: Int? = nil,
        userAttachmentLifetime: TestAttachmentLifetime? = nil,
        uiTestingScreenshotsLifetime: TestAttachmentLifetime? = nil,
        areLocalizationScreenshotsEnabled: Bool? = nil,
        diagnosticCollectionPolicy: TestDiagnosticCollectionPolicy? = nil,
        distributor: TestPlanDistributor? = nil,
        locationScenario: TestPlanLocationScenario? = nil,
        testInteropMode: TestInteropMode? = nil,
        applicationCrashDetectionSeverity: ApplicationCrashDetectionSeverity? = nil,
        addressSanitizer: TestPlanAddressSanitizer? = nil,
        threadSanitizerEnabled: Bool? = nil,
        mainThreadCheckerEnabled: Bool? = nil,
        performanceAntipatternCheckerEnabled: Bool? = nil,
        undefinedBehaviorSanitizerEnabled: Bool? = nil,
        zombieObjectsEnabled: Bool? = nil,
        guardMallocEnabled: Bool? = nil,
        mallocScribbleEnabled: Bool? = nil,
        mallocGuardEdgesEnabled: Bool? = nil,
        mallocStackLogging: TestPlanMallocStackLogging? = nil,
        checkedAllocations: TestPlanCheckedAllocations? = nil,
        runtimeIssueDetection: TestPlanRuntimeIssueDetectionPolicy? = nil,
        mainThreadCheckerDetectionPolicy: TestPlanRuntimeIssueDetectionPolicy? = nil,
        threadPerformanceCheckerRuntimeIssueDetection: TestPlanRuntimeIssueDetectionPolicy? = nil,
        memoryTaggingAddressSanitizerEnabled: Bool? = nil
    ) -> Self {
        Self(
            arguments: arguments,
            codeCoverage: codeCoverage,
            expandVariableFromTarget: expandVariableFromTarget,
            language: language,
            region: region,
            preferredScreenCaptureFormat: preferredScreenCaptureFormat,
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
            applicationCrashDetectionSeverity: applicationCrashDetectionSeverity,
            addressSanitizer: addressSanitizer,
            threadSanitizerEnabled: threadSanitizerEnabled,
            mainThreadCheckerEnabled: mainThreadCheckerEnabled,
            performanceAntipatternCheckerEnabled: performanceAntipatternCheckerEnabled,
            undefinedBehaviorSanitizerEnabled: undefinedBehaviorSanitizerEnabled,
            zombieObjectsEnabled: zombieObjectsEnabled,
            guardMallocEnabled: guardMallocEnabled,
            mallocScribbleEnabled: mallocScribbleEnabled,
            mallocGuardEdgesEnabled: mallocGuardEdgesEnabled,
            mallocStackLogging: mallocStackLogging,
            checkedAllocations: checkedAllocations,
            runtimeIssueDetection: runtimeIssueDetection,
            mainThreadCheckerDetectionPolicy: mainThreadCheckerDetectionPolicy,
            threadPerformanceCheckerRuntimeIssueDetection: threadPerformanceCheckerRuntimeIssueDetection,
            memoryTaggingAddressSanitizerEnabled: memoryTaggingAddressSanitizerEnabled
        )
    }
}
