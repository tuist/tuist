import FileSystem
import Foundation
import Path
import Testing
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting

@testable import TuistJobSummary

struct RunReportServiceTests {
    private let fileSystem = FileSystem()
    private let subject = RunReportService()

    private func makeReport(
        status: CommandEvent.Status = .success,
        testRunURL: URL? = URL(string: "https://tuist.dev/acme/app/tests/456"),
        buildRunURL: URL? = URL(string: "https://tuist.dev/acme/app/builds/789"),
        testRunReports: [RunReportTestRun] = [],
        buildRunReports: [RunReportBuildRun] = []
    ) -> RunReport {
        RunReport(
            runId: "run-id",
            status: status,
            runURL: URL(string: "https://tuist.dev/acme/app/runs/123")!,
            testRunURL: testRunURL,
            buildRunURL: buildRunURL,
            testRunReports: testRunReports,
            buildRunReports: buildRunReports
        )
    }

    private func readReport(at path: AbsolutePath) async throws -> RunReport {
        let content = try await fileSystem.readTextFile(at: path)
        return try JSONDecoder().decode(RunReport.self, from: Data(content.utf8))
    }

    @Test(.withMockedEnvironment())
    func writes_the_run_report_as_json() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        let path = cwd.appending(component: "run-report.json")

        await subject.writeRunReport(
            makeReport(
                testRunReports: [
                    RunReportTestRun(
                        scheme: "App",
                        totalTests: 10,
                        skippedTests: 2,
                        failedTestNames: ["CheckoutFlowTests.test_appliesDiscountCode"]
                    ),
                ],
                buildRunReports: [RunReportBuildRun(scheme: "App", succeeded: true, duration: 432)]
            ),
            to: path.pathString
        )

        let report = try await readReport(at: path)
        #expect(report.runId == "run-id")
        #expect(report.status == .success)
        #expect(report.testRuns.first?.scheme == "App")
        #expect(report.testRuns.first?.succeeded == false)
        #expect(report.testRuns.first?.ranTests == 8)
        #expect(report.testRuns.first?.failedTestNames == ["CheckoutFlowTests.test_appliesDiscountCode"])
        #expect(report.buildRuns.first?.durationInSeconds == 432)
    }

    /// The URLs are logged in mutually exclusive branches, so stdout can only ever carry one of
    /// them. The report carries every URL that exists for the run.
    @Test(.withMockedEnvironment())
    func emits_the_test_and_build_urls_together() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        let path = cwd.appending(component: "run-report.json")

        await subject.writeRunReport(makeReport(), to: path.pathString)

        let report = try await readReport(at: path)
        #expect(report.runURL.absoluteString == "https://tuist.dev/acme/app/runs/123")
        #expect(report.testRunURL?.absoluteString == "https://tuist.dev/acme/app/tests/456")
        #expect(report.buildRunURL?.absoluteString == "https://tuist.dev/acme/app/builds/789")
    }

    /// Unlike the GitHub job summary, which has nothing to render without them, the report is
    /// still worth writing with no test or build runs: the URLs are what consumers are after.
    @Test(.withMockedEnvironment())
    func writes_the_report_when_there_are_no_test_or_build_runs() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        let path = cwd.appending(component: "run-report.json")

        await subject.writeRunReport(makeReport(testRunURL: nil, buildRunURL: nil), to: path.pathString)

        let report = try await readReport(at: path)
        #expect(report.testRuns.isEmpty)
        #expect(report.buildRuns.isEmpty)
        #expect(report.runURL.absoluteString == "https://tuist.dev/acme/app/runs/123")
    }

    /// Retried CI jobs re-run against a workspace that still has the previous report in it.
    @Test(.withMockedEnvironment())
    func overwrites_an_existing_report() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        let path = cwd.appending(component: "run-report.json")
        try await fileSystem.writeText("stale", at: path, encoding: .utf8)

        await subject.writeRunReport(makeReport(), to: path.pathString)

        let report = try await readReport(at: path)
        #expect(report.runId == "run-id")
    }

    @Test(.withMockedEnvironment())
    func creates_intermediate_directories() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        let path = cwd.appending(components: ["reports", "nested", "run-report.json"])

        await subject.writeRunReport(makeReport(), to: path.pathString)

        #expect(try await fileSystem.exists(path) == true)
    }

    @Test(.withMockedEnvironment())
    func resolves_a_relative_path_against_the_working_directory() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()

        await subject.writeRunReport(makeReport(), to: "run-report.json")

        #expect(try await fileSystem.exists(cwd.appending(component: "run-report.json")) == true)
    }

    /// Reporting on a run must never be able to fail the run it's reporting on.
    @Test(.withMockedEnvironment())
    func does_not_throw_when_the_report_cannot_be_written() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        let path = cwd.appending(component: "occupied")
        // A file where the report's parent directory needs to be.
        try await fileSystem.writeText("", at: path, encoding: .utf8)

        await subject.writeRunReport(makeReport(), to: path.appending(component: "run-report.json").pathString)

        #expect(try await fileSystem.exists(path.appending(component: "run-report.json")) == false)
    }

    @Test(.withMockedEnvironment())
    func clears_a_report_left_behind_by_an_earlier_run() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        let path = cwd.appending(component: "run-report.json")
        try await fileSystem.writeText("stale", at: path, encoding: .utf8)

        await subject.clearRunReport(at: path.pathString)

        #expect(try await fileSystem.exists(path) == false)
    }

    @Test(.withMockedEnvironment())
    func clearing_a_report_that_is_not_there_is_a_no_op() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()

        await subject.clearRunReport(at: cwd.appending(component: "absent.json").pathString)
    }

    @Test(.withMockedEnvironment())
    func maps_a_failed_run_to_the_failure_status() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        let path = cwd.appending(component: "run-report.json")

        await subject.writeRunReport(makeReport(status: .failure("boom")), to: path.pathString)

        let report = try await readReport(at: path)
        #expect(report.status == .failure)
    }
}
