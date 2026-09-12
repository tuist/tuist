import Foundation
import Path

public enum TestPlanCodeCoverage: Equatable, Codable, Sendable {
    case disabled
    case allTargets
    case specificTargets([TargetReference])
}

public enum TestPlanAddressSanitizer: Equatable, Codable, Sendable {
    case disabled
    case enabled(detectStackUseAfterReturn: Bool)
}

public enum TestPlanCheckedAllocations: String, Codable, Sendable {
    case disabled
    case always
    case mteOnly
}

public enum TestPlanRuntimeIssueDetectionPolicy: Equatable, Codable, Sendable {
    case disabled
    case enabled(String)
}

/// Explicit values for a generated test-plan configuration.
public struct TestPlanOptions: Equatable, Codable, Sendable {
    public var arguments: Arguments?
    public var codeCoverage: TestPlanCodeCoverage?
    public var expandVariableFromTarget: TargetReference?
    public var language: String?
    public var region: String?
    public var preferredScreenCaptureFormat: ScreenCaptureFormat?
    public var testExecutionOrdering: String?
    public var parallelizationMode: String?
    public var testRepetitionMode: String?
    public var maximumTestRepetitions: Int?
    public var repeatInNewRunnerProcess: Bool?
    public var testTimeoutsEnabled: Bool?
    public var defaultTestExecutionTimeAllowance: Int?
    public var maximumTestExecutionTimeAllowance: Int?
    public var userAttachmentLifetime: String?
    public var uiTestingScreenshotsLifetime: String?
    public var areLocalizationScreenshotsEnabled: Bool?
    public var diagnosticCollectionPolicy: String?
    public var distributor: String?
    public var locationScenarioIdentifier: String?
    public var locationScenarioReferenceType: String?
    public var testInteropMode: String?
    public var applicationCrashDetectionSeverity: String?
    public var addressSanitizer: TestPlanAddressSanitizer?
    public var threadSanitizerEnabled: Bool?
    public var mainThreadCheckerEnabled: Bool?
    public var performanceAntipatternCheckerEnabled: Bool?
    public var undefinedBehaviorSanitizerEnabled: Bool?
    public var zombieObjectsEnabled: Bool?
    public var guardMallocEnabled: Bool?
    public var mallocScribbleEnabled: Bool?
    public var mallocGuardEdgesEnabled: Bool?
    public var mallocStackLogging: String?
    public var checkedAllocations: TestPlanCheckedAllocations?
    public var runtimeIssueDetection: TestPlanRuntimeIssueDetectionPolicy?
    public var mainThreadCheckerDetectionPolicy: TestPlanRuntimeIssueDetectionPolicy?
    public var threadPerformanceCheckerRuntimeIssueDetection: TestPlanRuntimeIssueDetectionPolicy?
    public var memoryTaggingAddressSanitizerEnabled: Bool?

    public init(
        arguments: Arguments? = nil,
        codeCoverage: TestPlanCodeCoverage? = nil,
        expandVariableFromTarget: TargetReference? = nil,
        language: String? = nil,
        region: String? = nil,
        preferredScreenCaptureFormat: ScreenCaptureFormat? = nil,
        testExecutionOrdering: String? = nil,
        parallelizationMode: String? = nil,
        testRepetitionMode: String? = nil,
        maximumTestRepetitions: Int? = nil,
        repeatInNewRunnerProcess: Bool? = nil,
        testTimeoutsEnabled: Bool? = nil,
        defaultTestExecutionTimeAllowance: Int? = nil,
        maximumTestExecutionTimeAllowance: Int? = nil,
        userAttachmentLifetime: String? = nil,
        uiTestingScreenshotsLifetime: String? = nil,
        areLocalizationScreenshotsEnabled: Bool? = nil,
        diagnosticCollectionPolicy: String? = nil,
        distributor: String? = nil,
        locationScenarioIdentifier: String? = nil,
        locationScenarioReferenceType: String? = nil,
        testInteropMode: String? = nil,
        applicationCrashDetectionSeverity: String? = nil,
        addressSanitizer: TestPlanAddressSanitizer? = nil,
        threadSanitizerEnabled: Bool? = nil,
        mainThreadCheckerEnabled: Bool? = nil,
        performanceAntipatternCheckerEnabled: Bool? = nil,
        undefinedBehaviorSanitizerEnabled: Bool? = nil,
        zombieObjectsEnabled: Bool? = nil,
        guardMallocEnabled: Bool? = nil,
        mallocScribbleEnabled: Bool? = nil,
        mallocGuardEdgesEnabled: Bool? = nil,
        mallocStackLogging: String? = nil,
        checkedAllocations: TestPlanCheckedAllocations? = nil,
        runtimeIssueDetection: TestPlanRuntimeIssueDetectionPolicy? = nil,
        mainThreadCheckerDetectionPolicy: TestPlanRuntimeIssueDetectionPolicy? = nil,
        threadPerformanceCheckerRuntimeIssueDetection: TestPlanRuntimeIssueDetectionPolicy? = nil,
        memoryTaggingAddressSanitizerEnabled: Bool? = nil
    ) {
        self.arguments = arguments
        self.codeCoverage = codeCoverage
        self.expandVariableFromTarget = expandVariableFromTarget
        self.language = language
        self.region = region
        self.preferredScreenCaptureFormat = preferredScreenCaptureFormat
        self.testExecutionOrdering = testExecutionOrdering
        self.parallelizationMode = parallelizationMode
        self.testRepetitionMode = testRepetitionMode
        self.maximumTestRepetitions = maximumTestRepetitions
        self.repeatInNewRunnerProcess = repeatInNewRunnerProcess
        self.testTimeoutsEnabled = testTimeoutsEnabled
        self.defaultTestExecutionTimeAllowance = defaultTestExecutionTimeAllowance
        self.maximumTestExecutionTimeAllowance = maximumTestExecutionTimeAllowance
        self.userAttachmentLifetime = userAttachmentLifetime
        self.uiTestingScreenshotsLifetime = uiTestingScreenshotsLifetime
        self.areLocalizationScreenshotsEnabled = areLocalizationScreenshotsEnabled
        self.diagnosticCollectionPolicy = diagnosticCollectionPolicy
        self.distributor = distributor
        self.locationScenarioIdentifier = locationScenarioIdentifier
        self.locationScenarioReferenceType = locationScenarioReferenceType
        self.testInteropMode = testInteropMode
        self.applicationCrashDetectionSeverity = applicationCrashDetectionSeverity
        self.addressSanitizer = addressSanitizer
        self.threadSanitizerEnabled = threadSanitizerEnabled
        self.mainThreadCheckerEnabled = mainThreadCheckerEnabled
        self.performanceAntipatternCheckerEnabled = performanceAntipatternCheckerEnabled
        self.undefinedBehaviorSanitizerEnabled = undefinedBehaviorSanitizerEnabled
        self.zombieObjectsEnabled = zombieObjectsEnabled
        self.guardMallocEnabled = guardMallocEnabled
        self.mallocScribbleEnabled = mallocScribbleEnabled
        self.mallocGuardEdgesEnabled = mallocGuardEdgesEnabled
        self.mallocStackLogging = mallocStackLogging
        self.checkedAllocations = checkedAllocations
        self.runtimeIssueDetection = runtimeIssueDetection
        self.mainThreadCheckerDetectionPolicy = mainThreadCheckerDetectionPolicy
        self.threadPerformanceCheckerRuntimeIssueDetection = threadPerformanceCheckerRuntimeIssueDetection
        self.memoryTaggingAddressSanitizerEnabled = memoryTaggingAddressSanitizerEnabled
    }
}

public struct TestPlan: Hashable, Codable, Sendable {
    /// How the `.xctestplan` file comes to exist on disk.
    public enum Kind: Equatable, Codable, Sendable {
        /// The file already exists on disk and is maintained by the user.
        case referenced
        /// The file is produced by Tuist during project generation.
        case generated(
            defaultOptions: TestPlanOptions = TestPlanOptions(),
            options: [String: TestPlanOptions] = ["Configuration 1": TestPlanOptions()]
        )

        public var isGenerated: Bool {
            if case .generated = self { return true }
            return false
        }
    }

    public let name: String
    public let path: AbsolutePath
    public let testTargets: [TestableTarget]
    public let isDefault: Bool
    public let kind: Kind

    public init(
        path: AbsolutePath,
        testTargets: [TestableTarget],
        isDefault: Bool,
        kind: Kind = .referenced
    ) {
        name = path.basenameWithoutExt
        self.path = path
        self.testTargets = testTargets
        self.isDefault = isDefault
        self.kind = kind
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}
