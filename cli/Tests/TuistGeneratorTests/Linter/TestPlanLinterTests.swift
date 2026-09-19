import Mockable
import Path
import Testing
import struct TSCUtility.Version
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
@testable import TuistGenerator

struct TestPlanLinterTests {
    private let subject = TestPlanLinter()

    @Test func lint_reportsMaximumTestRepetitionsBelowXcodeMinimum() {
        // Given
        let got = subject.lint(
            testPlan: testPlan(maximumTestRepetitions: 1),
            schemeName: "App",
            xcodeVersion: Version(27, 0, 0)
        )

        // Then
        #expect(got == [invalidValueIssue(option: "`maximumTestRepetitions`", minimumValue: 2)])
    }

    @Test func lint_reportsDefaultTestExecutionTimeAllowanceBelowXcodeMinimum() {
        // Given
        let got = subject.lint(
            testPlan: testPlan(defaultTestExecutionTimeAllowance: 59),
            schemeName: "App",
            xcodeVersion: Version(27, 0, 0)
        )

        // Then
        #expect(got == [invalidValueIssue(option: "`defaultTestExecutionTimeAllowance`", minimumValue: 60)])
    }

    @Test func lint_reportsMaximumTestExecutionTimeAllowanceBelowXcodeMinimum() {
        // Given
        let got = subject.lint(
            testPlan: testPlan(maximumTestExecutionTimeAllowance: 59),
            schemeName: "App",
            xcodeVersion: Version(27, 0, 0)
        )

        // Then
        #expect(got == [invalidValueIssue(option: "`maximumTestExecutionTimeAllowance`", minimumValue: 60)])
    }

    @Test func lint_validates_named_configurations_before_default_options() {
        // Given
        let plan = TestPlan(
            path: "/Project/TestPlan.xctestplan",
            testTargets: [],
            isDefault: true,
            kind: .generated(
                defaultOptions: TestPlanOptions(maximumTestExecutionTimeAllowance: 59),
                options: [
                    "Z": TestPlanOptions(maximumTestRepetitions: 1),
                    "A": TestPlanOptions(defaultTestExecutionTimeAllowance: 59),
                ]
            )
        )

        // When
        let got = subject.lint(
            testPlan: plan,
            schemeName: "App",
            xcodeVersion: Version(27, 0, 0)
        )

        // Then
        #expect(got == [
            invalidValueIssue(option: "`defaultTestExecutionTimeAllowance`", minimumValue: 60),
            invalidValueIssue(option: "`maximumTestRepetitions`", minimumValue: 2),
            invalidValueIssue(option: "`maximumTestExecutionTimeAllowance`", minimumValue: 60),
        ])
    }

    @Test(.withMockedXcodeController) func projectLinter_reportsUnsupportedGeneratedTestPlanOption() async throws {
        // Given
        let xcodeController = try #require(XcodeController.mocked)
        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 4, 0))
        let plan = testPlan(parallelizationMode: "automatic")
        let project = Project.test(
            settings: Settings(configurations: [
                BuildConfiguration.debug: .test(),
            ]),
            schemes: [
                .test(name: "App", testAction: .test(testPlans: [plan])),
            ]
        )

        // When
        let got = try await subject.lint(project: project)

        // Then
        #expect(got == [LintingIssue(
            reason: "The generated test plan 'TestPlan' in scheme 'App' uses `parallelizationMode`, which requires Xcode 16.0.0 or later. The selected Xcode version is 15.4.0.",
            severity: .error
        )])
    }

    @Test func lint_reportsUnsupportedParallelizationMode() {
        // Given
        let got = subject.lint(
            testPlan: testPlan(parallelizationMode: "automatic"),
            schemeName: "App",
            xcodeVersion: Version(15, 4, 0)
        )

        // Then
        #expect(got == [unsupportedFeatureIssue(feature: "`parallelizationMode`", minimumXcodeVersion: Version(16, 0, 0))])
    }

    @Test func lint_reportsUnsupportedPerformanceAntipatternChecker() {
        // Given
        let got = subject.lint(
            testPlan: testPlan(performanceAntipatternCheckerEnabled: true),
            schemeName: "App",
            xcodeVersion: Version(15, 4, 0)
        )

        // Then
        #expect(got == [unsupportedFeatureIssue(
            feature: "`performanceAntipatternCheckerEnabled`",
            minimumXcodeVersion: Version(26, 0, 0)
        )])
    }

    @Test func lint_reportsUnsupportedCheckedAllocations() {
        // Given
        let got = subject.lint(
            testPlan: testPlan(checkedAllocations: .always),
            schemeName: "App",
            xcodeVersion: Version(15, 4, 0)
        )

        // Then
        #expect(got == [unsupportedFeatureIssue(feature: "`checkedAllocations`", minimumXcodeVersion: Version(26, 0, 0))])
    }

    @Test func lint_reportsUnsupportedCheckedAllocationsHardwareRequirement() {
        // Given
        let got = subject.lint(
            testPlan: testPlan(checkedAllocations: .mteOnly),
            schemeName: "App",
            xcodeVersion: Version(15, 4, 0)
        )

        // Then
        #expect(got == [unsupportedFeatureIssue(feature: "`checkedAllocations`", minimumXcodeVersion: Version(26, 0, 0))])
    }

    @Test func lint_reportsUnsupportedMainThreadCheckerDetectionPolicy() {
        // Given
        let got = subject.lint(
            testPlan: testPlan(mainThreadCheckerDetectionPolicy: .enabled("error")),
            schemeName: "App",
            xcodeVersion: Version(15, 4, 0)
        )

        // Then
        #expect(got == [unsupportedFeatureIssue(
            feature: "`mainThreadCheckerDetectionPolicy`",
            minimumXcodeVersion: Version(26, 0, 0)
        )])
    }

    @Test func lint_reportsUnsupportedThreadPerformanceCheckerDetectionPolicy() {
        // Given
        let got = subject.lint(
            testPlan: testPlan(threadPerformanceCheckerRuntimeIssueDetection: .enabled("error")),
            schemeName: "App",
            xcodeVersion: Version(15, 4, 0)
        )

        // Then
        #expect(got == [unsupportedFeatureIssue(
            feature: "`threadPerformanceCheckerRuntimeIssueDetection`",
            minimumXcodeVersion: Version(26, 0, 0)
        )])
    }

    @Test func lint_allowsFeaturesSupportedBySelectedXcode() {
        // Given
        let got = subject.lint(
            testPlan: testPlan(
                performanceAntipatternCheckerEnabled: true,
                checkedAllocations: .always,
                mainThreadCheckerDetectionPolicy: .enabled("error"),
                threadPerformanceCheckerRuntimeIssueDetection: .enabled("error"),
                memoryTaggingAddressSanitizerEnabled: true
            ),
            schemeName: "App",
            xcodeVersion: Version(27, 0, 0)
        )

        // Then
        #expect(got.isEmpty)
    }

    @Test func lint_reportsUnsupportedTestInteropMode() {
        // Given
        let got = subject.lint(
            testPlan: testPlan(testInteropMode: "complete"),
            schemeName: "App",
            xcodeVersion: Version(26, 0, 0)
        )

        // Then
        #expect(got == [unsupportedFeatureIssue(
            feature: "`testInteropMode`",
            minimumXcodeVersion: Version(27, 0, 0),
            selectedXcodeVersion: Version(26, 0, 0)
        )])
    }

    @Test func lint_reportsUnsupportedApplicationCrashDetectionSeverity() {
        // Given
        let got = subject.lint(
            testPlan: testPlan(applicationCrashDetectionSeverity: "fatalFailure"),
            schemeName: "App",
            xcodeVersion: Version(26, 0, 0)
        )

        // Then
        #expect(got == [unsupportedFeatureIssue(
            feature: "`applicationCrashDetectionSeverity`",
            minimumXcodeVersion: Version(27, 0, 0),
            selectedXcodeVersion: Version(26, 0, 0)
        )])
    }

    @Test func lint_reportsUnsupportedMemoryTaggingAddressSanitizer() {
        // Given
        let got = subject.lint(
            testPlan: testPlan(memoryTaggingAddressSanitizerEnabled: true),
            schemeName: "App",
            xcodeVersion: Version(26, 0, 0)
        )

        // Then
        #expect(got == [unsupportedFeatureIssue(
            feature: "`memoryTaggingAddressSanitizerEnabled`",
            minimumXcodeVersion: Version(27, 0, 0),
            selectedXcodeVersion: Version(26, 0, 0)
        )])
    }

    private func testPlan(
        testInteropMode: String? = nil,
        applicationCrashDetectionSeverity: String? = nil,
        parallelizationMode: String? = nil,
        maximumTestRepetitions: Int? = nil,
        defaultTestExecutionTimeAllowance: Int? = nil,
        maximumTestExecutionTimeAllowance: Int? = nil,
        performanceAntipatternCheckerEnabled: Bool? = nil,
        checkedAllocations: TestPlanCheckedAllocations? = nil,
        mainThreadCheckerDetectionPolicy: TestPlanRuntimeIssueDetectionPolicy? = nil,
        threadPerformanceCheckerRuntimeIssueDetection: TestPlanRuntimeIssueDetectionPolicy? = nil,
        memoryTaggingAddressSanitizerEnabled: Bool? = nil
    ) -> TestPlan {
        TestPlan(
            path: "/Project/TestPlan.xctestplan",
            testTargets: [],
            isDefault: true,
            kind: .generated(defaultOptions: TestPlanOptions(
                parallelizationMode: parallelizationMode,
                maximumTestRepetitions: maximumTestRepetitions,
                defaultTestExecutionTimeAllowance: defaultTestExecutionTimeAllowance,
                maximumTestExecutionTimeAllowance: maximumTestExecutionTimeAllowance,
                testInteropMode: testInteropMode,
                applicationCrashDetectionSeverity: applicationCrashDetectionSeverity,
                performanceAntipatternCheckerEnabled: performanceAntipatternCheckerEnabled,
                checkedAllocations: checkedAllocations,
                mainThreadCheckerDetectionPolicy: mainThreadCheckerDetectionPolicy,
                threadPerformanceCheckerRuntimeIssueDetection: threadPerformanceCheckerRuntimeIssueDetection,
                memoryTaggingAddressSanitizerEnabled: memoryTaggingAddressSanitizerEnabled
            ))
        )
    }

    private func unsupportedFeatureIssue(
        feature: String,
        minimumXcodeVersion: Version,
        selectedXcodeVersion: Version = Version(15, 4, 0)
    ) -> LintingIssue {
        LintingIssue(
            reason: "The generated test plan 'TestPlan' in scheme 'App' uses \(feature), which requires Xcode \(minimumXcodeVersion) or later. The selected Xcode version is \(selectedXcodeVersion).",
            severity: .error
        )
    }

    private func invalidValueIssue(option: String, minimumValue: Int) -> LintingIssue {
        LintingIssue(
            reason: "The generated test plan 'TestPlan' in scheme 'App' sets \(option) below Xcode's minimum value of \(minimumValue).",
            severity: .error
        )
    }
}
