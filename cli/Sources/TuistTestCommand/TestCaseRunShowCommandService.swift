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

        let stackTraceURL = Self.stackTraceURL(
            run: run,
            serverURL: serverURL,
            fullHandle: resolvedFullHandle
        )

        if json {
            let jsonObject = TestCaseRunJSON(run: run, stackTraceURL: stackTraceURL)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(jsonObject)
            Noora.current.passthrough(TerminalText(stringLiteral: String(data: data, encoding: .utf8) ?? "{}"))
            return
        }

        let info = formatRunInfo(run)
        Noora.current.passthrough("\(info)")

        if let stackTrace = run.stack_trace {
            var summary: [String] = []
            summary.append("Stack Trace".bold())
            summary.append("  File:      \(stackTrace.file_name)")
            if let appName = stackTrace.app_name, !appName.isEmpty {
                summary.append("  App:       \(appName)")
            }
            if let osVersion = stackTrace.os_version, !osVersion.isEmpty {
                summary.append("  OS:        \(osVersion)")
            }
            if let exceptionType = stackTrace.exception_type, !exceptionType.isEmpty {
                summary.append("  Exception: \(exceptionType)")
            }
            if let signal = stackTrace.signal, !signal.isEmpty {
                summary.append("  Signal:    \(signal)")
            }
            if let subtype = stackTrace.exception_subtype, !subtype.isEmpty {
                summary.append("  Subtype:   \(subtype)")
            }
            Noora.current.passthrough("\(summary.joined(separator: "\n"))\n")
            if let stackTraceURL {
                Noora.current.passthrough("  \(.link(title: "Full stack trace", href: stackTraceURL))\n")
            }
            if let formattedFrames = stackTrace.formatted_frames, !formattedFrames.isEmpty {
                Noora.current.passthrough("\n\(formattedFrames)\n")
            }
        }
        Noora.current.passthrough("")
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

        return info.joined(separator: "\n") + "\n"
    }

    static func stackTraceURL(
        run: ServerTestCaseRun,
        serverURL: URL,
        fullHandle: String
    ) -> String? {
        guard let stackTrace = run.stack_trace else { return nil }
        let handles = fullHandle.split(separator: "/")
        guard handles.count == 2 else { return nil }
        return "\(serverURL.absoluteString)/\(handles[0])/\(handles[1])/tests/test-case-runs/\(run.id)/attachments/\(stackTrace.file_name)"
    }
}

private struct TestCaseRunJSON: Encodable {
    let run: ServerTestCaseRun
    let stackTraceURL: String?

    enum CodingKeys: String, CodingKey {
        case duration
        case failures
        case gitBranch = "git_branch"
        case gitCommitSha = "git_commit_sha"
        case id
        case isCi = "is_ci"
        case isFlaky = "is_flaky"
        case isNew = "is_new"
        case moduleName = "module_name"
        case name
        case ranAt = "ran_at"
        case repetitions
        case scheme
        case stackTrace = "stack_trace"
        case stackTraceURL = "stack_trace_url"
        case status
        case suiteName = "suite_name"
        case testCaseId = "test_case_id"
        case testRunId = "test_run_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(run.duration, forKey: .duration)
        try container.encode(run.failures, forKey: .failures)
        try container.encodeIfPresent(run.git_branch, forKey: .gitBranch)
        try container.encodeIfPresent(run.git_commit_sha, forKey: .gitCommitSha)
        try container.encode(run.id, forKey: .id)
        try container.encode(run.is_ci, forKey: .isCi)
        try container.encode(run.is_flaky, forKey: .isFlaky)
        try container.encode(run.is_new, forKey: .isNew)
        try container.encode(run.module_name, forKey: .moduleName)
        try container.encode(run.name, forKey: .name)
        try container.encodeIfPresent(run.ran_at, forKey: .ranAt)
        try container.encode(run.repetitions, forKey: .repetitions)
        try container.encodeIfPresent(run.scheme, forKey: .scheme)
        try container.encodeIfPresent(run.stack_trace, forKey: .stackTrace)
        try container.encodeIfPresent(stackTraceURL, forKey: .stackTraceURL)
        try container.encode(run.status, forKey: .status)
        try container.encodeIfPresent(run.suite_name, forKey: .suiteName)
        try container.encodeIfPresent(run.test_case_id, forKey: .testCaseId)
        try container.encodeIfPresent(run.test_run_id, forKey: .testRunId)
    }
}
