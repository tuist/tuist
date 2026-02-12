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
        var info: [String] = []

        // Test identity
        var testName = "\(run.module_name)"
        if let suiteName = run.suite_name, !suiteName.isEmpty {
            testName += "/\(suiteName)"
        }
        testName += "/\(run.name)"
        info.append(testName.bold())

        // Result
        info.append("")
        info.append("Result".bold())
        info.append("  Status:    \(run.status.rawValue)")
        info.append("  Duration:  \(Formatters.formatDuration(run.duration))")
        info.append("  Flaky:     \(run.is_flaky ? "Yes" : "No")")

        // Context
        info.append("")
        info.append("Context".bold())
        info.append("  CI:        \(run.is_ci ? "Yes" : "No")")
        if let scheme = run.scheme, !scheme.isEmpty {
            info.append("  Scheme:    \(scheme)")
        }
        if let gitBranch = run.git_branch, !gitBranch.isEmpty {
            info.append("  Branch:    \(gitBranch)")
        }
        if let gitCommitSha = run.git_commit_sha, !gitCommitSha.isEmpty {
            info.append("  Commit:    \(gitCommitSha)")
        }
        if let ranAt = run.ran_at {
            info.append("  Ran At:    \(Formatters.formatDate(ranAt))")
        }

        // IDs
        info.append("")
        info.append("IDs".bold())
        info.append("  Run:       \(run.id)")
        if let testRunId = run.test_run_id, !testRunId.isEmpty {
            info.append("  Test Run:  \(testRunId)")
        }

        // Failures
        if !run.failures.isEmpty {
            info.append("")
            info.append("Failures (\(run.failures.count))".bold())
            for (index, failure) in run.failures.enumerated() {
                if index > 0 { info.append("") }
                var location = ""
                if let path = failure.path {
                    location = path
                    if let lineNumber = failure.line_number {
                        location += ":\(lineNumber)"
                    }
                }

                var header = ""
                if let issueType = failure.issue_type, !issueType.isEmpty {
                    header = "  [\(issueType)]"
                    if !location.isEmpty { header += " \(location)" }
                } else if !location.isEmpty {
                    header = "  \(location)"
                }

                if !header.isEmpty { info.append(header) }
                info.append("  \(failure.message)")
            }
        }

        // Repetitions
        if !run.repetitions.isEmpty {
            info.append("")
            info.append("Repetitions (\(run.repetitions.count))".bold())
            for repetition in run.repetitions
                .sorted(by: { $0.repetition_number < $1.repetition_number })
            {
                let num = repetition.repetition_number
                let status = repetition.status.rawValue
                let duration = Formatters.formatDuration(repetition.duration)
                info.append("  #\(num): \(status)  \(duration)")
            }
        }

        // Stack Trace
        if let stackTrace = run.stack_trace {
            info.append("")
            info.append("Stack Trace".bold())
            info.append("  File:      \(stackTrace.file_name)")
            if let appName = stackTrace.app_name, !appName.isEmpty {
                info.append("  App:       \(appName)")
            }
            if let osVersion = stackTrace.os_version, !osVersion.isEmpty {
                info.append("  OS:        \(osVersion)")
            }
            if let exceptionType = stackTrace.exception_type, !exceptionType.isEmpty {
                info.append("  Exception: \(exceptionType)")
            }
            if let signal = stackTrace.signal, !signal.isEmpty {
                info.append("  Signal:    \(signal)")
            }
            if let subtype = stackTrace.exception_subtype, !subtype.isEmpty {
                info.append("  Subtype:   \(subtype)")
            }
            info.append("")
            info.append(stackTrace.raw_content)
        }

        return info.joined(separator: "\n") + "\n"
    }
}
