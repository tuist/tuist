import FileSystem
import Foundation
import Mockable
import Path
import TuistCI
import TuistCore
import TuistEnvironment
import TuistLogging

@Mockable
public protocol GitHubActionsJobSummaryServicing {
    /// Renders the per-run test and build results captured locally and appends them to the GitHub
    /// Actions job summary (`$GITHUB_STEP_SUMMARY`). It's a no-op unless there is something to report,
    /// the command is running in GitHub Actions, and the summary file is available. It never throws so
    /// it can't fail the command it's reporting on.
    ///
    /// Rendering happens entirely from locally-captured data so the summary is written immediately,
    /// without waiting for the server to finish processing the uploaded result bundle / activity log.
    /// `runURL` links to the dashboard run for the full report (flaky tests, bundle-size deltas, etc.).
    func writeJobSummary(
        testRunReports: [RunReportTestRun],
        buildRunReports: [RunReportBuildRun],
        runURL: URL
    ) async
}

public struct GitHubActionsJobSummaryService: GitHubActionsJobSummaryServicing {
    private let fileSystem: FileSysteming
    private let ciController: CIControlling

    public init(
        fileSystem: FileSysteming = FileSystem(),
        ciController: CIControlling = CIController()
    ) {
        self.fileSystem = fileSystem
        self.ciController = ciController
    }

    public func writeJobSummary(
        testRunReports: [RunReportTestRun],
        buildRunReports: [RunReportBuildRun],
        runURL: URL
    ) async {
        guard !testRunReports.isEmpty || !buildRunReports.isEmpty else { return }
        guard ciController.ciInfo()?.provider == .github else { return }
        guard let summaryPath = Environment.current.variables["GITHUB_STEP_SUMMARY"], !summaryPath.isEmpty else { return }

        let markdown = Self.render(
            testRunReports: testRunReports,
            buildRunReports: buildRunReports,
            runURL: runURL
        )

        do {
            let outputPath = try AbsolutePath(validating: summaryPath)
            let existing = (try? await fileSystem.readTextFile(at: outputPath)) ?? ""
            try await fileSystem.writeText(
                existing + markdown + "\n",
                at: outputPath,
                encoding: .utf8,
                options: [.overwrite]
            )
            Logger.current.debug("Wrote the Tuist Run Report to the GitHub Actions job summary.")
        } catch {
            Logger.current.debug("Failed to write the GitHub Actions job summary: \(String(describing: error))")
        }
    }

    static func render(
        testRunReports: [RunReportTestRun],
        buildRunReports: [RunReportBuildRun],
        runURL: URL
    ) -> String {
        var sections = ["### 🛠️ Tuist Run Report 🛠️"]

        if !testRunReports.isEmpty {
            sections.append(testsSection(testRunReports))

            let failedTestNames = testRunReports.flatMap(\.failedTestNames)
            if !failedTestNames.isEmpty {
                sections.append(failedTestsSection(failedTestNames))
            }
        }

        if !buildRunReports.isEmpty {
            sections.append(buildsSection(buildRunReports))
        }

        sections.append("[View the full report on Tuist](\(runURL.absoluteString))")

        return sections.joined(separator: "\n\n")
    }

    private static func testsSection(_ reports: [RunReportTestRun]) -> String {
        let rows = reports.map { report in
            "| \(report.scheme) | \(report.succeeded ? "✅" : "❌") | \(report.totalTests) | \(report.skippedTests) | \(report.ranTests) |"
        }
        return """
        #### Tests 🧪

        | Scheme | Status | Tests | Skipped | Ran |
        |:-:|:-:|:-:|:-:|:-:|
        \(rows.joined(separator: "\n"))
        """
    }

    private static func failedTestsSection(_ failedTestNames: [String]) -> String {
        let items = failedTestNames.map { "- `\($0)`" }
        return """
        #### Failed Tests ❌

        \(items.joined(separator: "\n"))
        """
    }

    private static func buildsSection(_ reports: [RunReportBuildRun]) -> String {
        let rows = reports.map { report in
            "| \(report.scheme) | \(report.succeeded ? "✅" : "❌") | \(formatDuration(report.duration)) |"
        }
        return """
        #### Builds 🔨

        | Scheme | Status | Duration |
        |:-:|:-:|:-:|
        \(rows.joined(separator: "\n"))
        """
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let remainingSeconds = total % 60
        return minutes > 0 ? "\(minutes)m \(remainingSeconds)s" : "\(remainingSeconds)s"
    }
}
