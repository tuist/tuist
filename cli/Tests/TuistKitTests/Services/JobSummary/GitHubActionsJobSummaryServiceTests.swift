import FileSystem
import Foundation
import Mockable
import Path
import Testing
import TuistCI
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting

@testable import TuistKit

struct GitHubActionsJobSummaryServiceTests {
    private let fileSystem = FileSystem()
    private let ciController = MockCIControlling()
    private let subject: GitHubActionsJobSummaryService

    init() {
        subject = GitHubActionsJobSummaryService(fileSystem: fileSystem, ciController: ciController)
    }

    @Test func render_includes_tests_builds_failed_tests_and_link() {
        let markdown = GitHubActionsJobSummaryService.render(
            testRunReports: [
                RunReportTestRun(scheme: "App", totalTests: 10, skippedTests: 2, failedTestNames: []),
                RunReportTestRun(
                    scheme: "AppUITests",
                    totalTests: 4,
                    skippedTests: 0,
                    failedTestNames: ["CheckoutFlowTests.test_appliesDiscountCode"]
                ),
            ],
            buildRunReports: [
                RunReportBuildRun(scheme: "App", succeeded: true, duration: 432),
                RunReportBuildRun(scheme: "AppUITests", succeeded: false, duration: 218),
            ],
            runURL: URL(string: "https://tuist.dev/acme/app/runs/123")!
        )

        #expect(markdown.contains("### 🛠️ Tuist Run Report 🛠️"))
        #expect(markdown.contains("#### Tests 🧪"))
        #expect(markdown.contains("| App | ✅ | 10 | 2 | 8 |"))
        #expect(markdown.contains("| AppUITests | ❌ | 4 | 0 | 4 |"))
        #expect(markdown.contains("#### Failed Tests ❌"))
        #expect(markdown.contains("- `CheckoutFlowTests.test_appliesDiscountCode`"))
        #expect(markdown.contains("#### Builds 🔨"))
        #expect(markdown.contains("| App | ✅ | 7m 12s |"))
        #expect(markdown.contains("| AppUITests | ❌ | 3m 38s |"))
        #expect(markdown.contains("[View the full report on Tuist](https://tuist.dev/acme/app/runs/123)"))
    }

    @Test func render_omits_empty_sections() {
        let markdown = GitHubActionsJobSummaryService.render(
            testRunReports: [RunReportTestRun(scheme: "App", totalTests: 3, skippedTests: 0, failedTestNames: [])],
            buildRunReports: [],
            runURL: URL(string: "https://tuist.dev/acme/app/runs/123")!
        )

        #expect(markdown.contains("#### Tests 🧪"))
        #expect(!markdown.contains("#### Failed Tests"))
        #expect(!markdown.contains("#### Builds"))
    }

    @Test(.withMockedEnvironment())
    func writes_report_to_github_step_summary() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        let summaryPath = cwd.appending(component: "step_summary")
        try await fileSystem.writeText("", at: summaryPath, encoding: .utf8)

        given(ciController).ciInfo().willReturn(.test(provider: .github))
        Environment.mocked?.variables["GITHUB_STEP_SUMMARY"] = summaryPath.pathString

        await subject.writeJobSummary(
            testRunReports: [RunReportTestRun(scheme: "App", totalTests: 3, skippedTests: 0, failedTestNames: [])],
            buildRunReports: [],
            runURL: URL(string: "https://tuist.dev/acme/app/runs/123")!
        )

        let content = try await fileSystem.readTextFile(at: summaryPath)
        #expect(content.contains("### 🛠️ Tuist Run Report 🛠️"))
        #expect(content.contains("| App | ✅ | 3 | 0 | 3 |"))
    }

    @Test(.withMockedEnvironment())
    func does_not_write_when_not_github_actions() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        let summaryPath = cwd.appending(component: "step_summary_gitlab")
        try await fileSystem.writeText("", at: summaryPath, encoding: .utf8)

        given(ciController).ciInfo().willReturn(.test(provider: .gitlab))
        Environment.mocked?.variables["GITHUB_STEP_SUMMARY"] = summaryPath.pathString

        await subject.writeJobSummary(
            testRunReports: [RunReportTestRun(scheme: "App", totalTests: 3, skippedTests: 0, failedTestNames: [])],
            buildRunReports: [],
            runURL: URL(string: "https://tuist.dev/acme/app/runs/123")!
        )

        let content = try await fileSystem.readTextFile(at: summaryPath)
        #expect(content == "")
    }

    @Test(.withMockedEnvironment())
    func does_not_write_when_there_is_nothing_to_report() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        let summaryPath = cwd.appending(component: "step_summary_empty")
        try await fileSystem.writeText("", at: summaryPath, encoding: .utf8)

        Environment.mocked?.variables["GITHUB_STEP_SUMMARY"] = summaryPath.pathString

        await subject.writeJobSummary(
            testRunReports: [],
            buildRunReports: [],
            runURL: URL(string: "https://tuist.dev/acme/app/runs/123")!
        )

        let content = try await fileSystem.readTextFile(at: summaryPath)
        #expect(content == "")
    }
}
