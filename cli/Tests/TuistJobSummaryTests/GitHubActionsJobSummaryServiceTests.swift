import FileSystem
import Foundation
import Mockable
import Path
import Testing
import TuistCI
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting

@testable import TuistJobSummary

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
                RunReportTestRun(
                    scheme: "App",
                    totalTests: 10,
                    skippedTests: 2,
                    failedTestNames: [],
                    ranTestModules: 3,
                    skippedTestModules: nil
                ),
                RunReportTestRun(
                    scheme: "AppUITests",
                    totalTests: 4,
                    skippedTests: 0,
                    failedTestNames: ["CheckoutFlowTests.test_appliesDiscountCode"],
                    ranTestModules: 1,
                    skippedTestModules: nil
                ),
            ],
            buildRunReports: [
                RunReportBuildRun(scheme: "App", succeeded: true, duration: 432),
                RunReportBuildRun(scheme: "AppUITests", succeeded: false, duration: 218),
            ],
            runURL: URL(string: "https://tuist.dev/acme/app/runs/123")!
        )

        #expect(markdown == """
        ### 🛠️ Tuist Run Report 🛠️

        #### Tests 🧪

        | Scheme | Status | Test modules | Test cases |
        |:-:|:-:|:-:|:-:|
        | App | ✅ | 3 | 10 |
        | AppUITests | ❌ | 1 | 4 |

        #### Failed Tests ❌

        - `CheckoutFlowTests.test_appliesDiscountCode`

        #### Builds 🔨

        | Scheme | Status | Duration |
        |:-:|:-:|:-:|
        | App | ✅ | 7m 12s |
        | AppUITests | ❌ | 3m 38s |

        [View the full report on Tuist](https://tuist.dev/acme/app/runs/123)
        """)
    }

    @Test func render_omits_empty_sections() {
        let markdown = GitHubActionsJobSummaryService.render(
            testRunReports: [RunReportTestRun(
                scheme: "App",
                totalTests: 3,
                skippedTests: 0,
                failedTestNames: [],
                ranTestModules: 1,
                skippedTestModules: nil
            )],
            buildRunReports: [],
            runURL: URL(string: "https://tuist.dev/acme/app/runs/123")!
        )

        #expect(markdown == """
        ### 🛠️ Tuist Run Report 🛠️

        #### Tests 🧪

        | Scheme | Status | Test modules | Test cases |
        |:-:|:-:|:-:|:-:|
        | App | ✅ | 1 | 3 |

        [View the full report on Tuist](https://tuist.dev/acme/app/runs/123)
        """)
    }

    @Test func render_shows_ran_test_modules_out_of_the_total_when_selective_testing_applied() {
        let markdown = GitHubActionsJobSummaryService.render(
            testRunReports: [
                RunReportTestRun(
                    scheme: "App",
                    totalTests: 1802,
                    skippedTests: 0,
                    failedTestNames: [],
                    ranTestModules: 18,
                    skippedTestModules: 28
                ),
                RunReportTestRun(
                    scheme: "AppUITests",
                    totalTests: 4,
                    skippedTests: 0,
                    failedTestNames: [],
                    ranTestModules: 1,
                    skippedTestModules: 0
                ),
            ],
            buildRunReports: [],
            runURL: URL(string: "https://tuist.dev/acme/app/runs/123")!
        )

        #expect(markdown == """
        ### 🛠️ Tuist Run Report 🛠️

        #### Tests 🧪

        | Scheme | Status | Test modules | Test cases |
        |:-:|:-:|:-:|:-:|
        | App | ✅ | 18/46 | 1802 |
        | AppUITests | ✅ | 1/1 | 4 |

        [View the full report on Tuist](https://tuist.dev/acme/app/runs/123)
        """)
    }

    @Test(.withMockedEnvironment())
    func writes_report_to_github_step_summary() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        let summaryPath = cwd.appending(component: "step_summary")
        try await fileSystem.writeText("", at: summaryPath, encoding: .utf8)

        given(ciController).ciInfo().willReturn(.test(provider: .github))
        Environment.mocked?.variables["GITHUB_STEP_SUMMARY"] = summaryPath.pathString

        await subject.writeJobSummary(
            testRunReports: [RunReportTestRun(
                scheme: "App",
                totalTests: 3,
                skippedTests: 0,
                failedTestNames: [],
                ranTestModules: 1,
                skippedTestModules: nil
            )],
            buildRunReports: [],
            runURL: URL(string: "https://tuist.dev/acme/app/runs/123")!
        )

        let content = try await fileSystem.readTextFile(at: summaryPath)
        #expect(content == """
        ### 🛠️ Tuist Run Report 🛠️

        #### Tests 🧪

        | Scheme | Status | Test modules | Test cases |
        |:-:|:-:|:-:|:-:|
        | App | ✅ | 1 | 3 |

        [View the full report on Tuist](https://tuist.dev/acme/app/runs/123)

        """)
    }

    @Test(.withMockedEnvironment())
    func does_not_write_when_not_github_actions() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        let summaryPath = cwd.appending(component: "step_summary_gitlab")
        try await fileSystem.writeText("", at: summaryPath, encoding: .utf8)

        given(ciController).ciInfo().willReturn(.test(provider: .gitlab))
        Environment.mocked?.variables["GITHUB_STEP_SUMMARY"] = summaryPath.pathString

        await subject.writeJobSummary(
            testRunReports: [RunReportTestRun(
                scheme: "App",
                totalTests: 3,
                skippedTests: 0,
                failedTestNames: [],
                ranTestModules: 1,
                skippedTestModules: nil
            )],
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
