import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

protocol TestShowCommandServicing {
    func run(
        project: String?,
        testRunId: String,
        path: String?,
        json: Bool
    ) async throws
}

enum TestShowCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't show the test run because the project is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct TestShowCommandService: TestShowCommandServicing {
    private let getTestRunService: GetTestRunServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        getTestRunService: GetTestRunServicing = GetTestRunService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.getTestRunService = getTestRunService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        project: String?,
        testRunId: String,
        path: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project ?? config.fullHandle else {
            throw TestShowCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let run = try await getTestRunService.getTestRun(
            fullHandle: resolvedFullHandle,
            testRunId: testRunId,
            serverURL: serverURL
        )

        if json {
            try Noora.current.json(run)
            return
        }

        let info = formatRunInfo(run)
        Noora.current.passthrough("\(info)")
        var nextSteps: [TerminalText] = [
            "\nNext steps:\n ▸ Run \(.command("tuist test case run list --test-run-id \(run.id)")) to see the test case runs\n",
        ]
        if run.selective_testing?.strategy == "coverage" {
            nextSteps.append(
                " ▸ Run \(.command("tuist test selective-testing list \(run.id)")) to see the tests coverage-based selection selected or skipped, and why\n"
            )
        }
        for step in nextSteps {
            Noora.current.passthrough(step)
        }
    }

    private func formatRunInfo(_ run: ServerTestRun) -> String {
        var info: [String] = []

        // Status header
        let statusLabel: String
        switch run.status {
        case "success": statusLabel = "passed"
        case "failure": statusLabel = "failed"
        case "in_progress": statusLabel = "in progress"
        default: statusLabel = run.status.replacingOccurrences(of: "_", with: " ")
        }
        info.append("Test Run (\(statusLabel))".bold())

        // Result
        info.append("")
        info.append("Result".bold())
        info.append("  Status:       \(run.status)")
        info.append("  Duration:     \(Formatters.formatDuration(run.duration))")
        info.append("  Flaky:        \(run.is_flaky ? "Yes" : "No")")

        // Test Metrics
        info.append("")
        info.append("Test Cases".bold())
        info.append("  Total:        \(run.total_test_count)")
        info.append("  Failed:       \(run.failed_test_count)")
        info.append("  Flaky:        \(run.flaky_test_count)")
        info.append("  Avg Duration: \(Formatters.formatDuration(run.avg_test_duration))")

        // Environment
        if run.macos_version != nil || run.xcode_version != nil || run.device_name != nil {
            info.append("")
            info.append("Environment".bold())
            if let deviceName = run.device_name, !deviceName.isEmpty {
                info.append("  Device:       \(deviceName)")
            }
            if let macosVersion = run.macos_version, !macosVersion.isEmpty {
                info.append("  macOS:        \(macosVersion)")
            }
            if let xcodeVersion = run.xcode_version, !xcodeVersion.isEmpty {
                info.append("  Xcode:        \(xcodeVersion)")
            }
        }

        // Context
        info.append("")
        info.append("Context".bold())
        info.append("  CI:           \(run.is_ci ? "Yes" : "No")")
        if let scheme = run.scheme, !scheme.isEmpty {
            info.append("  Scheme:       \(scheme)")
        }
        if let gitBranch = run.git_branch, !gitBranch.isEmpty {
            info.append("  Branch:       \(gitBranch)")
        }
        if let gitCommitSha = run.git_commit_sha, !gitCommitSha.isEmpty {
            info.append("  Commit:       \(gitCommitSha)")
        }
        if let ranAt = run.ran_at {
            info.append("  Ran At:       \(Formatters.formatDate(ranAt))")
        }

        // Coverage
        if let coverage = run.coverage, coverage.measured {
            info.append("")
            info.append("Coverage".bold())
            if let percentage = coverage.coverage, let covered = coverage.covered_lines,
               let executable = coverage.executable_lines
            {
                info.append("  Coverage:     \(String(format: "%.1f%%", percentage)) (\(covered) of \(executable) lines)")
            }
            if coverage.partial {
                info.append("  Partial:      Yes, it skipped tests on purpose, so it measured only what it ran")
            }
            if coverage.git_dirty {
                info.append("  Discarded:    Yes, it ran from a dirty checkout, so its coverage doesn't join its commit's")
            }
        }

        // Selective testing
        if let selectiveTesting = run.selective_testing {
            info.append("")
            info.append("Selective Testing".bold())
            info.append("  Strategy:     \(selectiveTesting.strategy)")
            if let baselineSHA = selectiveTesting.baseline_sha {
                info.append("  Baseline:     \(baselineSHA)")
            }
            info.append("  Requested:    \(selectiveTesting.requested)")
            info.append("  Selected:     \(selectiveTesting.selected)")
            info.append(
                selectiveTesting.estimated > 0
                    ? "  Skipped:      \(selectiveTesting.skipped) (\(selectiveTesting.estimated) estimated)"
                    : "  Skipped:      \(selectiveTesting.skipped)"
            )
        }

        // IDs
        info.append("")
        info.append("IDs".bold())
        info.append("  Run:          \(run.id)")

        return info.joined(separator: "\n") + "\n"
    }
}
