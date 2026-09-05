import Foundation
import struct TSCUtility.Version
import TuistCore
import TuistSupport
import XcodeGraph

/// Validates generated test-plan options against the selected Xcode version before Tuist writes the plan to disk.
///
/// Keep version requirements explicit here rather than discovering them from Xcode's private frameworks at runtime.
protocol TestPlanLinting {
    func lint(project: Project) async throws -> [LintingIssue]
}

struct TestPlanLinter: TestPlanLinting {
    func lint(project: Project) async throws -> [LintingIssue] {
        let generatedPlans = project.schemes.flatMap { scheme in
            (scheme.testAction?.testPlans ?? [])
                .filter(\.kind.isGenerated)
                .map { (scheme.name, $0) }
        }
        guard !generatedPlans.isEmpty else { return [] }

        let xcodeVersion = try await XcodeController.current.selectedVersion()
        return generatedPlans.flatMap { schemeName, testPlan in
            lint(testPlan: testPlan, schemeName: schemeName, xcodeVersion: xcodeVersion)
        }
    }

    /// Returns one error for every option in the test plan that the selected Xcode does not support.
    func lint(testPlan: TestPlan, schemeName: String, xcodeVersion: Version) -> [LintingIssue] {
        guard case let .generated(defaultOptions, options) = testPlan.kind else { return [] }
        let configurationIssues = options
            .sorted { $0.key < $1.key }
            .flatMap { _, options in
                lint(
                    options: options,
                    testPlan: testPlan,
                    schemeName: schemeName,
                    xcodeVersion: xcodeVersion
                )
            }
        let defaultOptionsIssues = lint(
            options: defaultOptions,
            testPlan: testPlan,
            schemeName: schemeName,
            xcodeVersion: xcodeVersion
        )
        return configurationIssues + defaultOptionsIssues
    }

    private func lint(
        options: TestPlanOptions,
        testPlan: TestPlan,
        schemeName: String,
        xcodeVersion: Version
    ) -> [LintingIssue] {
        [
            lintMinimumTestRepetitions(options: options, testPlan: testPlan, schemeName: schemeName),
            lintMinimumDefaultTestExecutionTimeAllowance(options: options, testPlan: testPlan, schemeName: schemeName),
            lintMinimumMaximumTestExecutionTimeAllowance(options: options, testPlan: testPlan, schemeName: schemeName),
            lintParallelizationMode(options: options, testPlan: testPlan, schemeName: schemeName, xcodeVersion: xcodeVersion),
            lintPerformanceAntipatternChecker(
                options: options,
                testPlan: testPlan,
                schemeName: schemeName,
                xcodeVersion: xcodeVersion
            ),
            lintCheckedAllocations(options: options, testPlan: testPlan, schemeName: schemeName, xcodeVersion: xcodeVersion),
            lintMainThreadCheckerDetectionPolicy(
                options: options,
                testPlan: testPlan,
                schemeName: schemeName,
                xcodeVersion: xcodeVersion
            ),
            lintThreadPerformanceCheckerDetectionPolicy(
                options: options,
                testPlan: testPlan,
                schemeName: schemeName,
                xcodeVersion: xcodeVersion
            ),
            lintTestInteropMode(options: options, testPlan: testPlan, schemeName: schemeName, xcodeVersion: xcodeVersion),
            lintApplicationCrashDetectionSeverity(
                options: options,
                testPlan: testPlan,
                schemeName: schemeName,
                xcodeVersion: xcodeVersion
            ),
            lintMemoryTaggingAddressSanitizer(
                options: options,
                testPlan: testPlan,
                schemeName: schemeName,
                xcodeVersion: xcodeVersion
            ),
        ].compactMap(\.self)
    }

    /// Validates Xcode's minimum number of repetitions when a maximum is configured.
    private func lintMinimumTestRepetitions(
        options: TestPlanOptions,
        testPlan: TestPlan,
        schemeName: String
    ) -> LintingIssue? {
        guard (options.maximumTestRepetitions ?? 2) < 2 else { return nil }
        return invalidValueIssue(
            option: "`maximumTestRepetitions`",
            minimumValue: 2,
            testPlan: testPlan,
            schemeName: schemeName
        )
    }

    /// Validates Xcode's minimum default per-test timeout of one minute.
    private func lintMinimumDefaultTestExecutionTimeAllowance(
        options: TestPlanOptions,
        testPlan: TestPlan,
        schemeName: String
    ) -> LintingIssue? {
        guard let defaultTestExecutionTimeAllowance = options.defaultTestExecutionTimeAllowance,
              defaultTestExecutionTimeAllowance < 60
        else { return nil }
        return invalidValueIssue(
            option: "`defaultTestExecutionTimeAllowance`",
            minimumValue: 60,
            testPlan: testPlan,
            schemeName: schemeName
        )
    }

    /// Validates Xcode's minimum maximum per-test timeout of one minute.
    private func lintMinimumMaximumTestExecutionTimeAllowance(
        options: TestPlanOptions,
        testPlan: TestPlan,
        schemeName: String
    ) -> LintingIssue? {
        guard let maximumTestExecutionTimeAllowance = options.maximumTestExecutionTimeAllowance,
              maximumTestExecutionTimeAllowance < 60
        else { return nil }
        return invalidValueIssue(
            option: "`maximumTestExecutionTimeAllowance`",
            minimumValue: 60,
            testPlan: testPlan,
            schemeName: schemeName
        )
    }

    /// Validates the global test-plan parallelization mode introduced in Xcode 16.
    private func lintParallelizationMode(
        options: TestPlanOptions,
        testPlan: TestPlan,
        schemeName: String,
        xcodeVersion: Version
    ) -> LintingIssue? {
        guard options.parallelizationMode != nil else { return nil }
        return unsupportedFeatureIssue(
            feature: "`parallelizationMode`",
            minimumXcodeVersion: Version(16, 0, 0),
            testPlan: testPlan,
            schemeName: schemeName,
            xcodeVersion: xcodeVersion
        )
    }

    /// Validates the Xcode 27 interoperability mode between Swift Testing and XCTest.
    private func lintTestInteropMode(
        options: TestPlanOptions,
        testPlan: TestPlan,
        schemeName: String,
        xcodeVersion: Version
    ) -> LintingIssue? {
        guard options.testInteropMode != nil else { return nil }
        return unsupportedFeatureIssue(
            feature: "`testInteropMode`",
            minimumXcodeVersion: Version(27, 0, 0),
            testPlan: testPlan,
            schemeName: schemeName,
            xcodeVersion: xcodeVersion
        )
    }

    /// Validates the Xcode 27 UI application crash detection policy.
    private func lintApplicationCrashDetectionSeverity(
        options: TestPlanOptions,
        testPlan: TestPlan,
        schemeName: String,
        xcodeVersion: Version
    ) -> LintingIssue? {
        guard options.applicationCrashDetectionSeverity != nil else { return nil }
        return unsupportedFeatureIssue(
            feature: "`applicationCrashDetectionSeverity`",
            minimumXcodeVersion: Version(27, 0, 0),
            testPlan: testPlan,
            schemeName: schemeName,
            xcodeVersion: xcodeVersion
        )
    }

    /// Validates the Xcode 27 Memory Tagging Address Sanitizer.
    private func lintMemoryTaggingAddressSanitizer(
        options: TestPlanOptions,
        testPlan: TestPlan,
        schemeName: String,
        xcodeVersion: Version
    ) -> LintingIssue? {
        guard options.memoryTaggingAddressSanitizerEnabled != nil else { return nil }
        return unsupportedFeatureIssue(
            feature: "`memoryTaggingAddressSanitizerEnabled`",
            minimumXcodeVersion: Version(27, 0, 0),
            testPlan: testPlan,
            schemeName: schemeName,
            xcodeVersion: xcodeVersion
        )
    }

    /// Validates the Thread Performance Checker introduced in Xcode 26.
    private func lintPerformanceAntipatternChecker(
        options: TestPlanOptions,
        testPlan: TestPlan,
        schemeName: String,
        xcodeVersion: Version
    ) -> LintingIssue? {
        guard options.performanceAntipatternCheckerEnabled != nil else { return nil }
        return unsupportedFeatureIssue(
            feature: "`performanceAntipatternCheckerEnabled`",
            minimumXcodeVersion: Version(26, 0, 0),
            testPlan: testPlan,
            schemeName: schemeName,
            xcodeVersion: xcodeVersion
        )
    }

    /// Validates Checked Allocations, which Xcode added in version 26.
    private func lintCheckedAllocations(
        options: TestPlanOptions,
        testPlan: TestPlan,
        schemeName: String,
        xcodeVersion: Version
    ) -> LintingIssue? {
        guard options.checkedAllocations != nil else { return nil }
        return unsupportedFeatureIssue(
            feature: "`checkedAllocations`",
            minimumXcodeVersion: Version(26, 0, 0),
            testPlan: testPlan,
            schemeName: schemeName,
            xcodeVersion: xcodeVersion
        )
    }

    /// Validates the Xcode 26 severity policy for Main Thread Checker issues.
    private func lintMainThreadCheckerDetectionPolicy(
        options: TestPlanOptions,
        testPlan: TestPlan,
        schemeName: String,
        xcodeVersion: Version
    ) -> LintingIssue? {
        guard options.mainThreadCheckerDetectionPolicy != nil else { return nil }
        return unsupportedFeatureIssue(
            feature: "`mainThreadCheckerDetectionPolicy`",
            minimumXcodeVersion: Version(26, 0, 0),
            testPlan: testPlan,
            schemeName: schemeName,
            xcodeVersion: xcodeVersion
        )
    }

    /// Validates the Xcode 26 severity policy for Thread Performance Checker issues.
    private func lintThreadPerformanceCheckerDetectionPolicy(
        options: TestPlanOptions,
        testPlan: TestPlan,
        schemeName: String,
        xcodeVersion: Version
    ) -> LintingIssue? {
        guard options.threadPerformanceCheckerRuntimeIssueDetection != nil else { return nil }
        return unsupportedFeatureIssue(
            feature: "`threadPerformanceCheckerRuntimeIssueDetection`",
            minimumXcodeVersion: Version(26, 0, 0),
            testPlan: testPlan,
            schemeName: schemeName,
            xcodeVersion: xcodeVersion
        )
    }

    /// Creates an error when a feature requires a newer Xcode than the selected one.
    private func unsupportedFeatureIssue(
        feature: String,
        minimumXcodeVersion: Version,
        testPlan: TestPlan,
        schemeName: String,
        xcodeVersion: Version
    ) -> LintingIssue? {
        guard xcodeVersion < minimumXcodeVersion else { return nil }
        return LintingIssue(
            reason: "The generated test plan '\(testPlan.name)' in scheme '\(schemeName)' uses \(feature), which requires Xcode \(minimumXcodeVersion) or later. The selected Xcode version is \(xcodeVersion).",
            severity: .error
        )
    }

    /// Creates an error when Xcode rejects an option value below its supported minimum.
    private func invalidValueIssue(
        option: String,
        minimumValue: Int,
        testPlan: TestPlan,
        schemeName: String
    ) -> LintingIssue {
        LintingIssue(
            reason: "The generated test plan '\(testPlan.name)' in scheme '\(schemeName)' sets \(option) below Xcode's minimum value of \(minimumValue).",
            severity: .error
        )
    }
}
