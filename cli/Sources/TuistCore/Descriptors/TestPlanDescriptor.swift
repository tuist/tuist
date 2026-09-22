@preconcurrency import AnyCodable
import CryptoKit
import Foundation
import Path
import XcodeGraph
import XcodeProj

/// Describes a generated `.xctestplan` file.
///
/// Unlike a `FileDescriptor`, the test targets are captured as references to `PBXTarget`
/// instances. Their PBX blueprint identifiers are only finalized when `XcodeProj` writes the
/// owning `.xcodeproj`, so the final JSON is assembled at side-effect execution time rather
/// than up front.
public struct TestPlanDescriptor: Equatable {
    public enum Error: Swift.Error, Equatable {
        case missingConfiguration(String)
    }

    /// Absolute path where the generated `.xctestplan` will be written.
    public let path: AbsolutePath
    /// Test targets included in the plan.
    public let testTargets: [TestTarget]
    public let defaultOptions: Options
    public let options: [String: Options]

    /// An option set after graph targets have been resolved to Xcode blueprint identifiers.
    public struct Options: Equatable {
        public let values: TestPlanOptions
        public let codeCoverageTargets: [TestTarget]?
        public let expandVariableFromTarget: TestTarget?

        public init(
            values: TestPlanOptions = TestPlanOptions(),
            codeCoverageTargets: [TestTarget]? = nil,
            expandVariableFromTarget: TestTarget? = nil
        ) {
            self.values = values
            self.codeCoverageTargets = codeCoverageTargets
            self.expandVariableFromTarget = expandVariableFromTarget
        }
    }

    public struct TestTarget: Equatable {
        /// Reference to the PBX target. Its `uuid` becomes the `identifier` in the test plan.
        public let pbxTarget: PBXTarget

        /// `container:` relative path to the `.xcodeproj` that owns the target, as used by Xcode.
        public let containerPath: String

        /// Whether the target runs or is skipped in the plan.
        public let isEnabled: Bool

        /// How the target's tests run in parallel. Controls the `parallelizable` field in the
        /// generated `.xctestplan`.
        public let parallelization: TestableTarget.Parallelization

        /// Test identifiers excluded from this target.
        public let skippedTests: [String]

        /// Test identifiers selected to run for this target.
        public let selectedTests: [String]

        public init(
            pbxTarget: PBXTarget,
            containerPath: String,
            isEnabled: Bool,
            parallelization: TestableTarget.Parallelization,
            skippedTests: [String] = [],
            selectedTests: [String] = []
        ) {
            self.pbxTarget = pbxTarget
            self.containerPath = containerPath
            self.isEnabled = isEnabled
            self.parallelization = parallelization
            self.skippedTests = skippedTests
            self.selectedTests = selectedTests
        }
    }

    public init(
        path: AbsolutePath,
        testTargets: [TestTarget],
        defaultOptions: Options = Options(),
        options: [String: Options] = ["Configuration 1": Options()]
    ) {
        self.path = path
        self.testTargets = testTargets
        self.defaultOptions = defaultOptions
        self.options = options
    }

    /// Encodes the descriptor into the Xcode `.xctestplan` JSON format.
    ///
    /// - Note: Must be called after the owning `.xcodeproj` has been written so that
    ///   `pbxTarget.uuid` returns stable blueprint identifiers.
    public func encode() throws -> Data {
        let plan = XCTestPlan(
            testTargets: testTargets.map { target in
                XCTestPlan.TestTarget(
                    target: XCTestPlan.TestTargetReference(
                        containerPath: target.containerPath,
                        identifier: target.pbxTarget.uuid,
                        name: target.pbxTarget.name
                    ),
                    enabled: target.isEnabled ? nil : false,
                    parallelizable: target.parallelization.xcTestPlanValue,
                    skippedTests: target.skippedTests.isEmpty ? nil : target.skippedTests,
                    selectedTests: target.selectedTests.isEmpty ? nil : target.selectedTests
                )
            },
            configurations: try options.keys.sorted().map { name in
                guard let configurationOptions = options[name] else {
                    throw Error.missingConfiguration(name)
                }
                return XCTestPlan.Configuration(
                    id: configurationID(for: name),
                    name: name,
                    options: optionsJSON(configurationOptions)
                )
            },
            defaultOptions: optionsJSON(defaultOptions),
            version: 1
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(plan)
    }

    private func optionsJSON(_ options: Options) -> [String: AnyCodable] {
        var result = basicOptionsJSON(options.values)
        result.merge(nestedOptionsJSON(options)) { _, new in new }
        return result
    }

    private func basicOptionsJSON(_ value: TestPlanOptions) -> [String: AnyCodable] {
        var result: [String: AnyCodable] = [:]

        func set(_ key: String, _ value: Any?) {
            if let value {
                result[key] = AnyCodable(value)
            }
        }

        set("testExecutionOrdering", value.testExecutionOrdering)
        set("parallelizationMode", value.parallelizationMode)
        set("testRepetitionMode", value.testRepetitionMode)
        set("maximumTestRepetitions", value.maximumTestRepetitions)
        set("repeatInNewRunnerProcess", value.repeatInNewRunnerProcess)
        set("testTimeoutsEnabled", value.testTimeoutsEnabled)
        set("defaultTestExecutionTimeAllowance", value.defaultTestExecutionTimeAllowance)
        set("maximumTestExecutionTimeAllowance", value.maximumTestExecutionTimeAllowance)
        set("userAttachmentLifetime", value.userAttachmentLifetime)
        set("uiTestingScreenshotsLifetime", value.uiTestingScreenshotsLifetime)
        set("areLocalizationScreenshotsEnabled", value.areLocalizationScreenshotsEnabled)
        set("diagnosticCollectionPolicy", value.diagnosticCollectionPolicy)
        set("distributor", value.distributor)
        set("testInteropMode", value.testInteropMode)
        set("applicationCrashDetectionSeverity", value.applicationCrashDetectionSeverity)
        set("language", value.language)
        set("region", value.region)
        set("preferredScreenCaptureFormat", value.preferredScreenCaptureFormat?.rawValue)
        set("threadSanitizerEnabled", value.threadSanitizerEnabled)
        set("mainThreadCheckerEnabled", value.mainThreadCheckerEnabled)
        set("performanceAntipatternCheckerEnabled", value.performanceAntipatternCheckerEnabled)
        set("undefinedBehaviorSanitizerEnabled", value.undefinedBehaviorSanitizerEnabled)
        set("nsZombieEnabled", value.zombieObjectsEnabled)
        set("guardMallocEnabled", value.guardMallocEnabled)
        set("mallocScribbleEnabled", value.mallocScribbleEnabled)
        set("mallocGuardEdgesEnabled", value.mallocGuardEdgesEnabled)
        set("memoryTaggingAddressSanitizerEnabled", value.memoryTaggingAddressSanitizerEnabled)
        return result
    }

    private func nestedOptionsJSON(_ options: Options) -> [String: AnyCodable] {
        let value = options.values
        var result: [String: AnyCodable] = [:]

        if let identifier = value.locationScenarioIdentifier, let referenceType = value.locationScenarioReferenceType {
            result["locationScenario"] = AnyCodable([
                "identifier": AnyCodable(identifier),
                "referenceType": AnyCodable(referenceType),
            ])
        }
        if let codeCoverage = codeCoverageJSON(value.codeCoverage, targets: options.codeCoverageTargets) {
            result["codeCoverage"] = codeCoverage
        }
        if let addressSanitizer = addressSanitizerJSON(value.addressSanitizer) {
            result["addressSanitizer"] = addressSanitizer
        }
        if let checkedAllocations = checkedAllocationsJSON(value.checkedAllocations) {
            result["checkedAllocations"] = checkedAllocations
        }
        if let logging = value.mallocStackLogging {
            result["mallocStackLoggingOptions"] = AnyCodable([
                "loggingType": AnyCodable(logging),
            ])
        }
        if let policy = runtimeIssueDetectionJSON(value.runtimeIssueDetection) {
            result["runtimeIssueDetection"] = policy
        }
        if let policy = runtimeIssueDetectionJSON(value.mainThreadCheckerDetectionPolicy) {
            result["mainThreadCheckerDetectionPolicy"] = policy
        }
        if let policy = runtimeIssueDetectionJSON(value.threadPerformanceCheckerRuntimeIssueDetection) {
            result["threadPerformanceCheckerRuntimeIssueDetection"] = policy
        }
        if let arguments = value.arguments {
            if !arguments.launchArguments.isEmpty {
                result["commandLineArgumentEntries"] = AnyCodable(arguments.launchArguments.map { [
                    "argument": AnyCodable($0.name),
                    "enabled": AnyCodable($0.isEnabled),
                ] })
            }
            if !arguments.environmentVariables.isEmpty {
                result["environmentVariableEntries"] = AnyCodable(arguments.environmentVariables.map { [
                    "key": AnyCodable($0.key),
                    "value": AnyCodable($0.value.value),
                    "enabled": AnyCodable($0.value.isEnabled),
                ] })
            }
        }
        if value.expandVariableFromTarget != nil, let target = options.expandVariableFromTarget {
            result["targetForVariableExpansion"] = AnyCodable(targetReference(target))
        }
        return result
    }

    private func addressSanitizerJSON(_ sanitizer: TestPlanAddressSanitizer?) -> AnyCodable? {
        guard let sanitizer else { return nil }
        return switch sanitizer {
        case .disabled:
            AnyCodable(["enabled": AnyCodable(false)])
        case let .enabled(detectStackUseAfterReturn):
            AnyCodable([
                "enabled": AnyCodable(true),
                "detectStackUseAfterReturn": AnyCodable(detectStackUseAfterReturn),
            ])
        }
    }

    private func codeCoverageJSON(
        _ codeCoverage: TestPlanCodeCoverage?,
        targets: [TestTarget]?
    ) -> AnyCodable? {
        guard let codeCoverage else { return nil }
        return switch codeCoverage {
        case .disabled:
            AnyCodable(false)
        case .allTargets:
            AnyCodable(true)
        case .specificTargets:
            AnyCodable([
                "targets": AnyCodable((targets ?? []).map(targetReference)),
            ])
        }
    }

    private func checkedAllocationsJSON(_ allocations: TestPlanCheckedAllocations?) -> AnyCodable? {
        guard let allocations else { return nil }
        return switch allocations {
        case .disabled:
            AnyCodable(["enabled": AnyCodable(false)])
        case .always:
            AnyCodable([
                "enabled": AnyCodable(true),
                "requiresHardwareAcceleration": AnyCodable(false),
            ])
        case .mteOnly:
            AnyCodable([
                "enabled": AnyCodable(true),
                "requiresHardwareAcceleration": AnyCodable(true),
            ])
        }
    }

    private func runtimeIssueDetectionJSON(_ policy: TestPlanRuntimeIssueDetectionPolicy?) -> AnyCodable? {
        guard let policy else { return nil }
        return switch policy {
        case .disabled:
            AnyCodable(["enabled": AnyCodable(false)])
        case let .enabled(severity):
            AnyCodable(["severity": AnyCodable(severity)])
        }
    }

    private func targetReference(_ target: TestTarget) -> [String: String] {
        [
            "containerPath": target.containerPath,
            "identifier": target.pbxTarget.uuid,
            "name": target.pbxTarget.name,
        ]
    }

    /// Deterministic UUID derived from the configuration name.
    ///
    /// Configuration names are unique within a test plan, so this keeps IDs stable across
    /// regenerations independently of the plan's checkout location.
    private func configurationID(for name: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }
}

extension TestableTarget.Parallelization {
    /// Maps parallelization onto the `parallelizable` field of an `.xctestplan`.
    ///
    /// Xcode treats an absent `parallelizable` as "Swift Testing only", so `swiftTestingOnly`
    /// returns `nil` (the key gets omitted during encoding).
    fileprivate var xcTestPlanValue: Bool? {
        switch self {
        case .all: true
        case .none: false
        case .swiftTestingOnly: nil
        }
    }
}
