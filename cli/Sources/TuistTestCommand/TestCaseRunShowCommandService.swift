import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

protocol TestCaseRunShowCommandServicing {
    func run(
        project: String?,
        testCaseRunId: String,
        path: String?,
        json: Bool
    ) async throws
}

enum TestCaseRunShowCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't show the test case run because the project is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct TestCaseRunShowCommandService: TestCaseRunShowCommandServicing {
    private let getTestCaseRunService: GetTestCaseRunServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        getTestCaseRunService: GetTestCaseRunServicing = GetTestCaseRunService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.getTestCaseRunService = getTestCaseRunService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        project: String?,
        testCaseRunId: String,
        path: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project ?? config.fullHandle else {
            throw TestCaseRunShowCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let run = try await getTestCaseRunService.getTestCaseRun(
            fullHandle: resolvedFullHandle,
            testCaseRunId: testCaseRunId,
            serverURL: serverURL
        )

        if json {
            try Noora.current.json(run)
            return
        }

        let info = formatRunInfo(run)
        Noora.current.passthrough("\(info)")
    }

    private func formatRunInfo(_ run: ServerTestCaseRun) -> String {
        var info = [
            "Test Case Run".bold(),
            "Name: \(run.name)",
            "Module: \(run.module_name)",
        ]

        if let suiteName = run.suite_name, !suiteName.isEmpty {
            info.append("Suite: \(suiteName)")
        }

        info.append("Status: \(run.status.rawValue)")
        info.append("Duration: \(Formatters.formatDuration(run.duration))")
        info.append("CI: \(run.is_ci ? "Yes" : "No")")
        info.append("Flaky: \(run.is_flaky ? "Yes" : "No")")

        if let scheme = run.scheme, !scheme.isEmpty {
            info.append("Scheme: \(scheme)")
        }

        if let gitBranch = run.git_branch, !gitBranch.isEmpty {
            info.append("Branch: \(gitBranch)")
        }

        if let gitCommitSha = run.git_commit_sha, !gitCommitSha.isEmpty {
            info.append("Commit: \(gitCommitSha)")
        }

        if let ranAt = run.ran_at {
            info.append("Ran At: \(Formatters.formatDate(ranAt))")
        }

        if !run.failures.isEmpty {
            info.append("")
            info.append("Failures".bold())
            for failure in run.failures {
                var location = ""
                if let path = failure.path {
                    location = path
                    if let lineNumber = failure.line_number {
                        location += ":\(lineNumber)"
                    }
                }

                if let issueType = failure.issue_type, !issueType.isEmpty {
                    if location.isEmpty {
                        info.append("[\(issueType)]")
                    } else {
                        info.append("[\(issueType)] \(location)")
                    }
                } else if !location.isEmpty {
                    info.append(location)
                }

                info.append("  \(failure.message)")
            }
        }

        if !run.repetitions.isEmpty {
            info.append("")
            info.append("Repetitions".bold())
            for repetition in run.repetitions.sorted(by: { $0.repetition_number < $1.repetition_number }) {
                info
                    .append(
                        "#\(repetition.repetition_number): \(repetition.status.rawValue)  \(Formatters.formatDuration(repetition.duration))"
                    )
            }
        }

        return info.joined(separator: "\n")
    }
}
