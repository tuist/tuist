import Foundation
import TuistCore

/// The machine-readable run report written to the path passed via `--run-report-path`
/// (or `TUIST_RUN_REPORT_PATH`).
///
/// Unlike the models it's built from, this type is a published contract: CI pipelines parse it to
/// get the dashboard URLs instead of scraping them out of the logs. Keeping it separate from
/// `CommandEvent` / `RunReportTestRun` / `RunReportBuildRun` means those stay free to change
/// without breaking consumers. Its format is documented in the "Run report" section of
/// `server/priv/docs/en/guides/integrations/continuous-integration.md`; keep the two in sync, and
/// only ever extend it in backwards-compatible ways.
public struct RunReport: Codable, Equatable {
    public let runId: String
    public let status: Status

    /// The dashboard URL for the run. Always present.
    public let runURL: URL

    /// The dashboard URL for the test run, when the command ran tests. Emitted independently of
    /// `buildRunURL`: a command that both builds and tests reports both.
    public let testRunURL: URL?

    /// The dashboard URL for the build run, when the command built.
    public let buildRunURL: URL?

    public let testRuns: [TestRun]
    public let buildRuns: [BuildRun]

    public enum Status: String, Codable {
        case success
        case failure
    }

    public struct TestRun: Codable, Equatable {
        public let scheme: String
        public let succeeded: Bool
        public let totalTests: Int
        public let skippedTests: Int
        public let ranTests: Int
        public let failedTestNames: [String]
    }

    public struct BuildRun: Codable, Equatable {
        public let scheme: String
        public let succeeded: Bool
        public let durationInSeconds: TimeInterval
    }

    public init(
        runId: String,
        status: CommandEvent.Status,
        runURL: URL,
        testRunURL: URL?,
        buildRunURL: URL?,
        testRunReports: [RunReportTestRun],
        buildRunReports: [RunReportBuildRun]
    ) {
        self.runId = runId
        self.status = switch status {
        case .success: .success
        case .failure: .failure
        }
        self.runURL = runURL
        self.testRunURL = testRunURL
        self.buildRunURL = buildRunURL
        testRuns = testRunReports.map {
            TestRun(
                scheme: $0.scheme,
                succeeded: $0.succeeded,
                totalTests: $0.totalTests,
                skippedTests: $0.skippedTests,
                ranTests: $0.ranTests,
                failedTestNames: $0.failedTestNames
            )
        }
        buildRuns = buildRunReports.map {
            BuildRun(
                scheme: $0.scheme,
                succeeded: $0.succeeded,
                durationInSeconds: $0.duration
            )
        }
    }
}
